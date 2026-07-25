import '../models/spend_map.dart';

/// Parses bank/UPI/wallet SMS (and short email snippets) into [FinanceTxn]s
/// entirely on-device with regex + keyword heuristics. No network, no LLM.
///
/// Returns null when a message is not a money movement (OTP, promo, balance
/// enquiry, reminders, etc.).
class FinanceMessageParser {
  const FinanceMessageParser();

  // Currency amount: Rs / Rs. / INR / ₹  followed by an amount, OR a bare
  // amount followed by a currency word. Captures the numeric group.
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

  static const _debitWords = [
    'debited',
    'debit',
    'spent',
    'paid',
    'withdrawn',
    'withdrawal',
    'purchase',
    'deducted',
    'charged',
    'sent to',
    'txn of',
    'transferred',
  ];

  static const _creditWords = [
    'credited',
    'received',
    'deposited',
    'added to',
    'refund',
  ];

  static const _salaryWords = [
    'salary',
    'sal cr',
    'sal-cr',
    'payroll',
    'sal credit',
    'monthly sal',
  ];

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
  static const _cardCreditExceptions = ['refund', 'cashback', 'reversed', 'reversal'];

  static bool _isCreditCardBillPayment(String lowerBody) {
    if (!_creditCardMentionRe.hasMatch(lowerBody)) return false;
    return !_cardCreditExceptions.any(lowerBody.contains);
  }

  // Skip these outright — not real completed transactions.
  static const _skipWords = [
    'otp',
    'one time password',
    'do not share',
    'will be debited',
    'will be deducted',
    'due on',
    'is due',
    'requested money',
    'requesting',
    'e-mandate',
    'autopay',
    'has been set',
    'failed',
    'declined',
    'reversed',
    'reversal',
  ];

  // Match skip words on word boundaries so a substring inside a merchant name
  // (e.g. "declined" appearing in a brand) cannot wrongly drop a real txn.
  static final RegExp _skipRe =
      RegExp('\\b(?:${_skipWords.join('|')})\\b', caseSensitive: false);

  // merchant/keyword → category. First match wins.
  static const Map<String, List<String>> _categoryKeywords = {
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
      'licious',
      'country delight',
      'milkbasket',
    ],
    SpendCategory.transport: [
      'uber',
      'ola',
      'rapido',
      'irctc',
      'petrol',
      'fuel',
      'hpcl',
      'iocl',
      'bpcl',
      'metro',
      'fastag',
      'redbus',
      'namma yatri',
      'blusmart',
      'yulu',
      'indian oil',
    ],
    SpendCategory.shopping: [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'nykaa',
      'tatacliq',
      'reliance digital',
      'croma',
      'lenskart',
      'decathlon',
      'ikea',
    ],
    SpendCategory.entertainment: [
      'netflix',
      'spotify',
      'hotstar',
      'prime video',
      'bookmyshow',
      'pvr',
      'inox',
      'youtube premium',
      'jiocinema',
      'sonyliv',
      'zee5',
      'disney',
    ],
    SpendCategory.bills: [
      'recharge',
      'electricity',
      'bescom',
      'bill',
      'jio',
      'airtel',
      'vi ',
      'broadband',
      'gas',
      'water bill',
      'dth',
      'postpaid',
      'tata power',
      'adani',
      'act fibernet',
      'bsnl',
      'insurance premium',
    ],
    SpendCategory.health: [
      'pharmeasy',
      'apollo',
      '1mg',
      'netmeds',
      'hospital',
      'clinic',
      'diagnostic',
      'medplus',
      'practo',
      'cult.fit',
      'cultfit',
    ],
    SpendCategory.rent: [
      'rent',
      'nobroker',
      'landlord',
    ],
    SpendCategory.investment: [
      'sip',
      'mutual fund',
      'zerodha',
      'groww',
      'upstox',
      'nps',
      'ppf',
      'stock',
      'indmoney',
      'kuvera',
    ],
    SpendCategory.cash: [
      'atm',
      'cash withdrawal',
      'cash wdl',
    ],
  };

  // Max characters of the original SMS body retained on a transaction for the
  // in-app "view original" detail. Enough to identify the message; short enough
  // to keep persisted storage lean.
  static const _bodyPreviewMax = 180;

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
    // large sentinel when a list has no match, so a single comparison also
    // handles the debit-only / credit-only cases.
    final debitAt = _firstIndexOf(lower, _debitWords);
    final creditAt = _firstIndexOf(lower, _creditWords);
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

    // 4. Salary detection (only meaningful for credits; a card bill payment
    // is never salary even though it may contain "credited").
    final isSalary = !isCardBillPayment &&
        direction == TxnDirection.credit &&
        _salaryWords.any(lower.contains);

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
      merchant: merchant,
      sender: sender,
      smsId: smsId,
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
    return inferRecurringSalary(_deduplicate(result));
  }

  /// Drops duplicate alerts for the same transaction. Banks and UPI apps often
  /// send two SMS (different sender headers, similar bodies) for one payment;
  /// keeping both double-counts spend and income. Two txns with the same
  /// amount, direction and calendar day are treated as one. This can merge two
  /// genuinely-distinct same-amount payments on the same day, but that is far
  /// rarer than duplicate alerts and much less distorting.
  static List<FinanceTxn> _deduplicate(List<FinanceTxn> txns) {
    final seen = <String>{};
    final out = <FinanceTxn>[];
    for (final t in txns) {
      final key = '${t.amount}|${t.direction.name}|'
          '${t.date.year}-${t.date.month}-${t.date.day}';
      if (seen.add(key)) out.add(t);
    }
    return out;
  }

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
    // Prefer an amount that is NOT immediately described as a balance.
    final matches = _amountRe.allMatches(lowerBody).toList();
    if (matches.isEmpty) return null;
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
    // Fall back to the first amount if all looked like balances.
    return _toInt(matches.first.group(1));
  }

  int? _toInt(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(',', '');
    final asDouble = double.tryParse(cleaned);
    return asDouble?.round();
  }

  static const _noMatch = 1 << 30;

  int _firstIndexOf(String body, List<String> words) {
    var best = _noMatch;
    for (final w in words) {
      final i = body.indexOf(w);
      if (i >= 0 && i < best) best = i;
    }
    return best;
  }

  // Merchant patterns: "at MERCHANT on", "to MERCHANT", "VPA merchant@bank".
  static final RegExp _merchantRe = RegExp(
    r'(?:\bat\b|\bto\b|\bfor\b)\s+([A-Za-z0-9&._ -]{2,40}?)(?:\s+on\b|\s+ref\b|\.|,|$)',
    caseSensitive: false,
  );
  static final RegExp _vpaRe =
      RegExp(r'([a-z0-9._-]+)@[a-z]+', caseSensitive: false);

  String? _extractMerchant(String body) {
    final atMatch = _merchantRe.firstMatch(body);
    final vpaMatch = _vpaRe.firstMatch(body);
    final raw = atMatch?.group(1)?.trim() ?? vpaMatch?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.length > 30 ? raw.substring(0, 30) : raw;
  }

  String _categorize(String lowerBody, String? merchant) {
    final haystack = '$lowerBody ${merchant?.toLowerCase() ?? ''}';
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (haystack.contains(kw)) return entry.key;
      }
    }
    return SpendCategory.other;
  }
}
