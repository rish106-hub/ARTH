import '../models/spend_map.dart';

/// Parses bank/UPI/wallet SMS (and short email snippets) into [FinanceTxn]s
/// entirely on-device with regex + keyword heuristics. No network, no LLM.
///
/// Returns null when a message is not a money movement (OTP, promo, balance
/// enquiry, reminders, etc.).
class FinanceMessageParser {
  const FinanceMessageParser();

  // ---------------------------------------------------------------- amounts

  // Currency amount: Rs / Rs. / INR / ₹ followed by an amount. Captures the
  // numeric group.
  static final RegExp _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // Worded amounts: "Rs 1.5 lakh", "2 crore" (currency prefix optional because
  // the unit word makes it unambiguous). "cr"/"l" single-letter units are
  // deliberately excluded — "CR" collides with the credit marker.
  static final RegExp _wordedAmountRe = RegExp(
    r'(?:rs\.?|inr|₹)?\s*([0-9]+(?:\.[0-9]+)?)\s*(lakhs?|lacs?|crores?)\b',
    caseSensitive: false,
  );

  // Amount with NO currency prefix. SBI/BoB/Canara UPI alerts write "A/C X1234
  // debited by 250.0 ... trf to SWIGGY" — without this the whole message was
  // discarded. Anchored immediately after a money verb (with only linking words
  // in between) so an account tail, date or reference number can never be read
  // as an amount.
  static final RegExp _bareAmountRe = RegExp(
    r'\b(?:debited|credited|debit|credit|paid|payment|sent|spent|withdrawn|'
    r'deducted|charged|transferred|trf)\b'
    r'(?:\s+(?:by|for|with|of|amount|amt|rs|inr))*'
    r'\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b',
    caseSensitive: false,
  );

  // ------------------------------------------------------------- direction

  // Direction verbs are matched on word boundaries: bare `contains` let
  // "debit" fire inside unrelated words. "sent" (not just "sent to") is
  // required for HDFC's dominant UPI format — "Sent Rs.120 From A/C x1 To X".
  static final RegExp _debitRe = RegExp(
    r'\b(?:debited|debit|spent|paid|withdrawn|withdrawal|purchase|deducted|'
    r'charged|sent|txn of|transferred|trf)\b',
    caseSensitive: false,
  );

  static final RegExp _creditRe = RegExp(
    r'\b(?:credited|received|deposited|added to|refund|refunded)\b',
    caseSensitive: false,
  );

  static final RegExp _salaryRe = RegExp(
    r'\b(?:salary|sal cr|sal-cr|sal credit|payroll|monthly sal)\b',
    caseSensitive: false,
  );

  // Credit-card BILL PAYMENTS read as a literal credit ("Payment of Rs X
  // received... credited to your SBI Credit Card ending 1234") because the
  // words "received"/"credited" appear before any debit verb. From the user's
  // perspective this is money LEAVING their bank account to pay a card bill —
  // an expense, not income. Matched on the phrase "credit card" appearing
  // anywhere in the body; excludes refund/cashback SMS, where a credit TO the
  // card really is money back and the normal credit-word heuristic is correct.
  static final RegExp _creditCardMentionRe = RegExp(
    r'\bcredit\s*card\b',
    caseSensitive: false,
  );
  static const _cardCreditExceptions = [
    'refund',
    'cashback',
    'reversed',
    'reversal'
  ];

  static bool _isCreditCardBillPayment(String lowerBody) {
    if (!_creditCardMentionRe.hasMatch(lowerBody)) return false;
    return !_cardCreditExceptions.any(lowerBody.contains);
  }

  // Paying a card bill produces a leg on the paying bank ("debited ... towards
  // ICICI Credit Card payment") and an acknowledgement from the card itself
  // ("Payment of Rs X received towards your ICICI Credit Card"). Both describe
  // the same money, and neither is spending: the spending already happened at
  // each purchase. Matching requires an explicit "towards <card>" or
  // "card payment" phrasing, so an ordinary purchase ("spent on your Credit
  // Card at SWIGGY") is untouched.
  static final RegExp _cardRepaymentRe = RegExp(
    r'\btowards\s+(?:your\s+)?(?:\w+\s+){0,3}credit\s*card'
    r'|credit\s*card\s+(?:bill\s+)?(?:payment|paid)'
    r'|payment\s+(?:towards|to)\s+(?:your\s+)?(?:\w+\s+){0,3}credit\s*card',
    caseSensitive: false,
  );

  /// Whether this message describes repaying the user's own credit card, in
  /// either direction. A refund or reversal to the card is real money back, so
  /// it is excluded.
  static bool _isCardRepayment(String lowerBody) {
    if (!_cardRepaymentRe.hasMatch(lowerBody)) return false;
    return !_cardCreditExceptions.any(lowerBody.contains);
  }

  // Skip these outright — not real completed transactions. Note that "autopay"
  // and "e-mandate" are deliberately NOT here: a mandate DEBIT is a real
  // expense (Netflix, SIPs, insurance). Only mandate *registration* and
  // future-tense notices are skipped.
  static const _skipWords = [
    'otp',
    'one time password',
    'do not share',
    'will be debited',
    'will be deducted',
    'will be charged',
    'due on',
    'is due',
    'requested money',
    'requesting',
    'has been set',
    'mandate registered',
    'mandate created',
    'mandate is successfully',
    'failed',
    'declined',
    'reversed',
    'reversal',
  ];

  // Match skip words on word boundaries so a substring inside a merchant name
  // (e.g. "declined" appearing in a brand) cannot wrongly drop a real txn.
  static final RegExp _skipRe =
      RegExp('\\b(?:${_skipWords.join('|')})\\b', caseSensitive: false);

  // ------------------------------------------------------------ categories

  // merchant/keyword → category. Order matters: the first category whose
  // keywords match wins, so narrower categories are listed before the broader
  // ones they would otherwise be swallowed by ("metro cash" as groceries
  // before "metro rail" as transport; "school" as education before "fee" as
  // fees).
  //
  // Bare brand names that belong to several unrelated businesses are
  // DELIBERATELY ABSENT — "apollo" (pharmacy, hospital, tyres, insurance),
  // "metro" (wholesale grocer, city rail, shoe shop), "indigo" (airline,
  // paint), "shell" (fuel), "reliance", "tata", "bajaj", "lic". Only their
  // qualified forms appear. Guessing from the bare name is how a transaction
  // ends up confidently mis-filed with nobody ever asked about it; left
  // unmatched it falls through to the AI pass and then to the user, which is
  // the correct outcome for a name that genuinely does not identify a business.
  // Do not "helpfully" add the short forms back.
  static const Map<String, List<String>> _categoryKeywords = {
    SpendCategory.insurance: [
      'insurance',
      'policy premium',
      'renewal premium',
      'lic premium',
      'lic of india',
      'hdfc ergo',
      'icici lombard',
      'bajaj allianz',
      'star health',
      'niva bupa',
      'acko',
      'go digit',
      'godigit',
      'policybazaar',
      'tata aig',
      'sbi life',
      'max life',
    ],
    SpendCategory.investment: [
      'sip',
      'mutual fund',
      'zerodha',
      'groww',
      'upstox',
      'angel one',
      'nps',
      'ppf',
      'elss',
      'smallcase',
      'demat',
      'broking',
      'stocks',
      'indmoney',
      'kuvera',
      'recurring deposit',
      'fixed deposit',
    ],
    SpendCategory.loan: [
      'emi',
      'loan',
      'nbfc',
      'finserv',
      'bajaj finance',
      'muthoot',
      'hdb financial',
      'kreditbee',
      'moneyview',
      'principal outstanding',
    ],
    SpendCategory.groceries: [
      'bigbasket',
      'blinkit',
      'zepto',
      'dmart',
      'grofers',
      'jiomart',
      'instamart',
      'grocery',
      'kirana',
      'supermarket',
      'super market',
      'metro cash',
      'metro wholesale',
      'reliance fresh',
      'reliance smart',
      'spencers',
      'natures basket',
      'licious',
      'country delight',
      'milkbasket',
    ],
    SpendCategory.food: [
      'swiggy',
      'zomato',
      'dominos',
      'mcdonald',
      'kfc',
      'restaurant',
      'cafe',
      'eatclub',
      'dineout',
      'eatsure',
      'faasos',
      'behrouz',
      'starbucks',
      'dhaba',
      'bakery',
      'biryani',
      'pizza',
      'burger',
      'chai',
      'sweets',
      'canteen',
      'tiffin',
    ],
    SpendCategory.education: [
      'school',
      'college',
      'tuition',
      'university',
      'coaching',
      'semester',
      'hostel fee',
      'admission',
      'exam fee',
      'coursera',
      'udemy',
      'unacademy',
      'byju',
      'vedantu',
      'physicswallah',
      'upgrad',
      'scaler',
    ],
    SpendCategory.travel: [
      'makemytrip',
      'goibibo',
      'yatra',
      'cleartrip',
      'ixigo',
      'oyo',
      'airbnb',
      'agoda',
      'booking.com',
      'indigo airlines',
      'goindigo',
      'air india',
      'vistara',
      'spicejet',
      'akasa',
      'airlines',
      'flight',
      'irctc',
      'railway',
      'redbus',
      'abhibus',
      'hotels',
      'resort',
      'homestay',
      'travel',
      'travels',
      'tours',
      'rental',
      'zoomcar',
      'revv',
    ],
    SpendCategory.transport: [
      'uber',
      'ola',
      'rapido',
      'petrol',
      'fuel',
      'hpcl',
      'iocl',
      'bpcl',
      'indian oil',
      'shell petrol',
      'shell fuel',
      'nayara',
      'metro rail',
      'metro card',
      'dmrc',
      'bmrcl',
      'fastag',
      'toll',
      'parking',
      'namma yatri',
      'blusmart',
      'yulu',
      'bounce',
      'apollo tyres',
      'tyre',
    ],
    SpendCategory.pets: [
      'vet',
      'veterinary',
      'petsmart',
      'heads up for tails',
      'supertails',
      'pet food',
      'pet shop',
      'drools',
      'pedigree',
    ],
    SpendCategory.gifts: [
      'donation',
      'donate',
      'charity',
      'ngo',
      'temple',
      'gurudwara',
      'church',
      'trust fund',
      'gift card',
      'giftcard',
      'ferns n petals',
      'fnp',
      'igp',
    ],
    SpendCategory.personalCare: [
      'salon',
      'spa',
      'barber',
      'parlour',
      'grooming',
      'urban company',
      'bblunt',
      'naturals salon',
      'lakme salon',
    ],
    SpendCategory.health: [
      'pharmeasy',
      'apollo 24',
      '1mg',
      'netmeds',
      'hospital',
      'clinic',
      'diagnostic',
      'pathlab',
      'pathlabs',
      'medplus',
      'pharmacy',
      'medical',
      'dental',
      'dentist',
      'physio',
      'practo',
      'cult.fit',
      'cultfit',
    ],
    SpendCategory.entertainment: [
      'netflix',
      'spotify',
      'hotstar',
      'prime video',
      'bookmyshow',
      'pvr',
      'inox',
      'cinepolis',
      'cinema',
      'multiplex',
      'theatre',
      'youtube premium',
      'jiocinema',
      'sonyliv',
      'zee5',
      'disney',
      'gaming',
    ],
    SpendCategory.subscriptions: [
      'subscription',
      'renewal',
      'membership',
      'icloud',
      'google one',
      'microsoft 365',
      'office 365',
      'adobe',
      'chatgpt',
      'openai',
      'notion',
      'canva',
      'github',
      'dropbox',
      'audible',
      'kindle unlimited',
      'apple one',
      'youtube music',
    ],
    SpendCategory.shopping: [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'nykaa',
      'tatacliq',
      'snapdeal',
      'firstcry',
      'reliance digital',
      'vijay sales',
      'croma',
      'lenskart',
      'decathlon',
      'ikea',
      'indigo paints',
      'zudio',
      'pantaloons',
      'westside',
      'shoppers stop',
      'bata',
      'tanishq',
      'caratlane',
    ],
    SpendCategory.bills: [
      'recharge',
      'electricity',
      'bescom',
      'msedcl',
      'torrent power',
      'tata power',
      'adani',
      'tneb',
      'kseb',
      'bill',
      'jio',
      'airtel',
      'vodafone',
      'vi postpaid',
      'bsnl',
      'broadband',
      'act fibernet',
      'wifi',
      'landline',
      'dth',
      'postpaid',
      'prepaid',
      'gas',
      'indane',
      'bharat gas',
      'mahanagar gas',
      'water bill',
      'utility',
    ],
    SpendCategory.fees: [
      'charge',
      'charges',
      'fee',
      'fees',
      'gst',
      'penalty',
      'late fee',
      'annual maintenance',
      'amc',
      'convenience fee',
      'processing fee',
      'sms charges',
      'minimum balance',
      'surcharge',
      'service tax',
    ],
    SpendCategory.rent: [
      'rent',
      'nobroker',
      'landlord',
      'house rent',
      'society maintenance',
      'flat maintenance',
    ],
    SpendCategory.cash: [
      'atm',
      'cash withdrawal',
      'cash wdl',
      'cardless cash',
    ],
  };

  static final RegExp _regexSpecials = RegExp(r'[.*+?^${}()|[\]\\]');

  static String _escape(String literal) =>
      literal.replaceAllMapped(_regexSpecials, (m) => '\\${m[0]}');

  static final RegExp _wordCharStart = RegExp(r'^\w');
  static final RegExp _wordCharEnd = RegExp(r'\w$');

  /// Anchors a keyword on word boundaries so `sip` no longer fires inside
  /// "gossip", `bill` inside "billdesk" or `metro` inside a longer token. The
  /// boundary is only added on an edge that is actually a word character, so
  /// punctuated keywords ("cult.fit", "booking.com") still match.
  static String _asWord(String keyword) {
    final left = _wordCharStart.hasMatch(keyword) ? r'\b' : '';
    final right = _wordCharEnd.hasMatch(keyword) ? r'\b' : '';
    return '$left${_escape(keyword)}$right';
  }

  static final List<(String, RegExp)> _categoryMatchers = [
    for (final entry in _categoryKeywords.entries)
      (
        entry.key,
        RegExp(entry.value.map(_asWord).join('|'), caseSensitive: false),
      ),
  ];

  // ------------------------------------------------------------- merchants

  // Merchant follows "to", "at" or "for". The trailing delimiter is a lookahead
  // so it is not swallowed, which keeps the captured span tight.
  static final RegExp _merchantRe = RegExp(
    r"(?:\bto\b|\bat\b|\bfor\b)\s+([A-Za-z0-9&./'_ -]{2,60}?)"
    r'(?=\s+on\b|\s+ref|\s+via\b|\s+upi\b|\s+dt\b|[.,;!]|$)',
    caseSensitive: false,
  );

  static final RegExp _vpaRe =
      RegExp(r'([a-z0-9._-]+)@[a-z]+', caseSensitive: false);

  // "for UPI to SWIGGY" / "for purchase at METRO CASH AND CARRY" — the real
  // merchant is the last segment, after the innermost preposition.
  static final RegExp _innerPrepositionRe =
      RegExp(r'\s+(?:to|at)\s+', caseSensitive: false);

  // Tokens that are transport wrapping, not part of the merchant name.
  static const _merchantNoiseTokens = {
    'a/c',
    'ac',
    'acct',
    'account',
    'avl',
    'bal',
    'bank',
    'by',
    'card',
    'dt',
    'for',
    'from',
    'imps',
    'info',
    'neft',
    'no',
    'of',
    'on',
    'payment',
    'pymt',
    'ref',
    'refno',
    'rtgs',
    'ach',
    'sent',
    'the',
    'through',
    'to',
    'towards',
    'transaction',
    'trf',
    'txn',
    'upi',
    'via',
    'vpa',
    'your',
  };

  // A masked account tail ("XX1234", "x1234", "****9012") or a bare number is
  // never the merchant.
  static final RegExp _accountTokenRe =
      RegExp(r'^(?:[x*]+[0-9]*|[0-9]+)$', caseSensitive: false);

  // "Rs 99.00", "1,299" — the amount, captured because it followed "for".
  static final RegExp _amountLikeRe = RegExp(
    r'^(?:rs\.?|inr|₹)?[\s.]*[0-9][0-9,.]*$',
    caseSensitive: false,
  );

  static final RegExp _refRe = RegExp(
    r'\b(?:ref(?:no|erence)?|utr|rrn|txn(?:\s*(?:id|no))?|upi)\b[\s:.#/-]*'
    r'([0-9]{6,20})\b',
    caseSensitive: false,
  );

  // Max characters of the original SMS body retained on a transaction for the
  // in-app "view original" detail. Enough to identify the message; short enough
  // to keep persisted storage lean.
  static const _bodyPreviewMax = 180;
  static const _merchantMax = 30;

  FinanceTxn? parse({
    required String sender,
    required String body,
    required DateTime date,
    int? smsId,
  }) {
    final lower = body.toLowerCase();

    // 1. Discard non-transactional noise.
    if (_skipRe.hasMatch(lower)) return null;

    // 2. Amount.
    final amount = _extractAmount(lower);
    if (amount == null || amount <= 0) return null;

    // 3. Direction. Whichever verb appears first wins; _firstIndexOf returns a
    // large sentinel when neither matches, so a single comparison also handles
    // the debit-only / credit-only cases.
    final debitAt = _firstIndexOf(lower, _debitRe);
    final creditAt = _firstIndexOf(lower, _creditRe);
    if (debitAt == _noMatch && creditAt == _noMatch) return null;
    var direction =
        debitAt < creditAt ? TxnDirection.debit : TxnDirection.credit;

    // A credit-card BILL PAYMENT ("Payment of Rs X received towards your HDFC
    // Credit Card") only reaches here as a credit because "received"/"credited"
    // literally appears — but it's money LEAVING the user's account, not
    // income. Only reclassify when the heuristic above actually got it wrong
    // (i.e. it picked credit); an ordinary card purchase ("spent on your
    // Credit Card at SWIGGY") already resolves to debit and is untouched, so
    // its merchant-based category isn't clobbered into "bills".
    final isCardBillPayment =
        direction == TxnDirection.credit && _isCreditCardBillPayment(lower);
    if (isCardBillPayment) direction = TxnDirection.debit;

    // Repaying a card moves money between the user's own accounts, so it is
    // recorded but excluded from spend. The purchases on that card are the
    // expense, and counting the bill as well would count the same money twice.
    final isCardRepayment = isCardBillPayment || _isCardRepayment(lower);

    // 4. Salary detection (only meaningful for credits; a card bill payment
    // is never salary even though it may contain "credited").
    final isSalary = !isCardRepayment &&
        direction == TxnDirection.credit &&
        _salaryRe.hasMatch(lower);

    // 5. Category + merchant (only for spend).
    final merchant = _extractMerchant(body);
    final category = isCardBillPayment
        ? SpendCategory.bills
        : direction == TxnDirection.debit
            ? _categorize(lower, merchant)
            : SpendCategory.other;

    return FinanceTxn(
      amount: amount,
      direction: direction,
      date: date,
      category: category,
      isSalary: isSalary,
      isInternalTransfer: isCardRepayment,
      merchant: merchant,
      sender: sender,
      smsId: smsId,
      refNo: _refRe.firstMatch(body)?.group(1),
      bodyPreview: _preview(body),
    );
  }

  static String _preview(String body) {
    final trimmed = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.length > _bodyPreviewMax
        ? '${trimmed.substring(0, _bodyPreviewMax)}…'
        : trimmed;
  }

  /// Parse a batch, dropping non-transactions and duplicate alerts, then infer
  /// recurring salary.
  List<FinanceTxn> parseAll(
    Iterable<({int? id, String sender, String body, DateTime date})> messages,
  ) {
    final result = <FinanceTxn>[];
    for (final m in messages) {
      final txn = parse(
        sender: m.sender,
        body: m.body,
        date: m.date,
        smsId: m.id,
      );
      if (txn != null) result.add(txn);
    }
    return inferRecurringSalary(
      _markInternalTransfers(_deduplicate(result)),
    );
  }

  /// Drops duplicate alerts for the same transaction. Banks and UPI apps often
  /// send two SMS (different sender headers, similar bodies) for one payment;
  /// keeping both double-counts spend and income.
  ///
  /// Prefers the UPI/NEFT reference number, which both alerts for one payment
  /// share and no two distinct payments share. Without a reference we fall back
  /// to amount + direction + day + merchant; including the merchant is what
  /// stops two genuinely different same-amount payments on one day (two ₹50
  /// chai runs) from collapsing into one, which the earlier key did.
  static List<FinanceTxn> _deduplicate(List<FinanceTxn> txns) {
    final seen = <String>{};
    final out = <FinanceTxn>[];
    for (final t in txns) {
      final ref = t.refNo;
      final key = ref != null && ref.isNotEmpty
          // Direction is part of the key: a transfer between the user's own
          // accounts reports the SAME reference as a debit on one side and a
          // credit on the other. Keying on the reference alone silently dropped
          // whichever leg arrived second, so the surviving leg was decided by
          // SMS arrival order — and a surviving credit could then be inferred
          // as salary.
          ? 'ref:$ref|${t.direction.name}'
          : '${t.amount}|${t.direction.name}|'
              '${t.date.year}-${t.date.month}-${t.date.day}|'
              '${_merchantKey(t.merchant)}';
      if (seen.add(key)) out.add(t);
    }
    return out;
  }

  /// Marks both ends of a movement between the user's own accounts.
  ///
  /// One UPI/NEFT reference appearing as both a debit and a credit is the two
  /// halves of one transfer — money left one account and arrived in another the
  /// user also owns. Neither half is spend or income. This is what stops a
  /// three-hop card payment (bank -> bank -> card) reading as several times the
  /// money that actually moved.
  ///
  /// Deliberately requires a shared reference rather than guessing from equal
  /// amounts on the same day: a same-size expense and credit that happen to
  /// coincide would otherwise both be hidden.
  static List<FinanceTxn> _markInternalTransfers(List<FinanceTxn> txns) {
    final byRef = <String, List<int>>{};
    for (var i = 0; i < txns.length; i++) {
      final ref = txns[i].refNo;
      if (ref == null || ref.isEmpty) continue;
      (byRef[ref] ??= <int>[]).add(i);
    }

    final internal = <int>{};
    byRef.forEach((_, indices) {
      if (indices.length < 2) return;
      final hasDebit =
          indices.any((i) => txns[i].direction == TxnDirection.debit);
      final hasCredit =
          indices.any((i) => txns[i].direction == TxnDirection.credit);
      if (hasDebit && hasCredit) internal.addAll(indices);
    });

    if (internal.isEmpty) return txns;
    return [
      for (var i = 0; i < txns.length; i++)
        internal.contains(i)
            ? txns[i].copyWith(isInternalTransfer: true, isSalary: false)
            : txns[i],
    ];
  }

  static final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]');

  static String _merchantKey(String? merchant) =>
      (merchant ?? '').toLowerCase().replaceAll(_nonAlphanumeric, '');

  // A recurring credit smaller than this is treated as a refund/cashback/P2P,
  // not salary.
  static const _minRecurringSalary = 10000;
  // Same-size credits are bucketed to the nearest this many rupees so a small
  // month-to-month variance (variable pay, rounding) still groups together.
  static const _salaryBucketRupees = 500;

  /// Second pass: bank salary credits (NEFT/IMPS/RTGS/ACH) rarely contain a
  /// "salary" keyword, so [parse] tags them as ordinary credits. Detect them by
  /// structure instead — a same-size credit that recurs across two or more
  /// distinct months is almost certainly recurring income.
  ///
  /// Tags every qualifying group (so multiple income streams are all counted),
  /// but at most ONE credit per calendar month per group. Without that cap, two
  /// same-size credits landing in the same month (a split payout, a bonus, or a
  /// duplicate that slipped past dedup) would both be summed into
  /// `salaryCredited` and inflate the monthly-income average.
  static List<FinanceTxn> inferRecurringSalary(List<FinanceTxn> txns) {
    final buckets = <int, List<int>>{};
    for (var i = 0; i < txns.length; i++) {
      final t = txns[i];
      if (t.isInternalTransfer) continue;
      if (t.direction != TxnDirection.credit || t.isSalary) continue;
      if (t.amount < _minRecurringSalary) continue;
      final key = (t.amount / _salaryBucketRupees).round();
      (buckets[key] ??= <int>[]).add(i);
    }

    final toTag = <int>{};
    buckets.forEach((key, indices) {
      // Keep the largest credit per month within this amount group.
      final byMonth = <int, int>{};
      for (final i in indices) {
        final month = txns[i].date.year * 12 + txns[i].date.month;
        final current = byMonth[month];
        if (current == null || txns[i].amount > txns[current].amount) {
          byMonth[month] = i;
        }
      }
      if (byMonth.length < 2) return; // not recurring across months
      toTag.addAll(byMonth.values);
    });

    if (toTag.isEmpty) return txns;
    return [
      for (var i = 0; i < txns.length; i++)
        toTag.contains(i) ? txns[i].copyWith(isSalary: true) : txns[i],
    ];
  }

  int? _extractAmount(String lowerBody) {
    // Worded amounts ("1.5 lakh") first — they are explicit and unambiguous.
    final worded = _wordedAmountRe.firstMatch(lowerBody);
    if (worded != null) {
      final value = double.tryParse(worded.group(1)!);
      if (value != null && value > 0) {
        final unit = worded.group(2)!;
        final multiplier = unit.startsWith('cr') ? 10000000 : 100000;
        return (value * multiplier).round();
      }
    }
    // Prefer a currency-prefixed amount that is NOT described as a balance.
    final matches = _amountRe.allMatches(lowerBody).toList();
    for (final m in matches) {
      final tail = lowerBody.substring(m.end).trimLeft();
      // Skip "...bal is Rs X" style balances.
      final headStart = m.start - 12 < 0 ? 0 : m.start - 12;
      final head = lowerBody.substring(headStart, m.start);
      if (head.contains('bal') ||
          head.contains('available') ||
          tail.startsWith('is your')) {
        continue;
      }
      final value = _toInt(m.group(1));
      if (value != null && value > 0) return value;
    }
    // No usable prefixed amount: try the verb-anchored bare amount.
    final bare = _toInt(_bareAmountRe.firstMatch(lowerBody)?.group(1));
    if (bare != null && bare > 0) return bare;
    // Fall back to the first prefixed amount if all looked like balances.
    return matches.isEmpty ? null : _toInt(matches.first.group(1));
  }

  int? _toInt(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(',', '');
    final asDouble = double.tryParse(cleaned);
    return asDouble?.round();
  }

  static const _noMatch = 1 << 30;

  int _firstIndexOf(String body, RegExp pattern) =>
      pattern.firstMatch(body)?.start ?? _noMatch;

  String? _extractMerchant(String body) {
    for (final match in _merchantRe.allMatches(body)) {
      final cleaned = _cleanMerchant(match.group(1));
      if (cleaned != null) return cleaned;
    }
    return _cleanMerchant(_vpaRe.firstMatch(body)?.group(1));
  }

  /// Reduces a raw capture to the merchant name, or null when nothing usable is
  /// left. Without this the captured span leaked the amount ("Rs 99"), wrapping
  /// words ("purchase at METRO...") and account tails ("XX12 by NEFT") into the
  /// merchant shown in the UI and fed to the categoriser.
  static String? _cleanMerchant(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;

    // "for UPI to SWIGGY" → "SWIGGY".
    value = value.split(_innerPrepositionRe).last;

    var tokens =
        value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    bool isNoise(String token) {
      final bare = token.toLowerCase().replaceAll(RegExp(r'[.,;:]+$'), '');
      return bare.isEmpty ||
          _merchantNoiseTokens.contains(bare) ||
          _accountTokenRe.hasMatch(bare);
    }

    while (tokens.isNotEmpty && isNoise(tokens.first)) {
      tokens = tokens.sublist(1);
    }
    while (tokens.isNotEmpty && isNoise(tokens.last)) {
      tokens = tokens.sublist(0, tokens.length - 1);
    }
    if (tokens.isEmpty) return null;

    final merchant = tokens.join(' ').trim().replaceAll(RegExp(r'^[-.]+'), '');
    if (merchant.length < 2 || _amountLikeRe.hasMatch(merchant)) return null;
    return merchant.length > _merchantMax
        ? merchant.substring(0, _merchantMax)
        : merchant;
  }

  /// Categorises on the merchant name first and only then on the whole body.
  /// Matching the merchant alone avoids bank names, reference strings and other
  /// body noise pulling a transaction into the wrong category.
  String _categorize(String lowerBody, String? merchant) {
    if (merchant != null && merchant.isNotEmpty) {
      final fromMerchant = _matchCategory(merchant.toLowerCase());
      if (fromMerchant != null) return fromMerchant;
    }
    return _matchCategory(lowerBody) ?? SpendCategory.other;
  }

  static String? _matchCategory(String haystack) {
    for (final (category, pattern) in _categoryMatchers) {
      if (pattern.hasMatch(haystack)) return category;
    }
    return null;
  }
}
