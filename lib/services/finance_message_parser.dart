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

  static const _debitWords = [
    'debited',
    'debit',
    'spent',
    'paid',
    'withdrawn',
    'purchase',
    'deducted',
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
  ];

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
    ],
    SpendCategory.cash: [
      'atm',
      'cash withdrawal',
      'cash wdl',
    ],
  };

  FinanceTxn? parse({
    required String sender,
    required String body,
    required DateTime date,
  }) {
    final lower = body.toLowerCase();

    // 1. Discard non-transactional noise.
    for (final skip in _skipWords) {
      if (lower.contains(skip)) return null;
    }

    // 2. Amount.
    final amount = _extractAmount(lower);
    if (amount == null || amount <= 0) return null;

    // 3. Direction. Whichever verb appears first wins; _firstIndexOf returns a
    // large sentinel when a list has no match, so a single comparison also
    // handles the debit-only / credit-only cases.
    final debitAt = _firstIndexOf(lower, _debitWords);
    final creditAt = _firstIndexOf(lower, _creditWords);
    if (debitAt == _noMatch && creditAt == _noMatch) return null;
    final direction =
        debitAt < creditAt ? TxnDirection.debit : TxnDirection.credit;

    // 4. Salary detection (only meaningful for credits).
    final isSalary =
        direction == TxnDirection.credit && _salaryWords.any(lower.contains);

    // 5. Category + merchant (only for spend).
    final merchant = _extractMerchant(body);
    final category = direction == TxnDirection.debit
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
    );
  }

  /// Parse a batch, dropping non-transactions.
  List<FinanceTxn> parseAll(
    Iterable<({String sender, String body, DateTime date})> messages,
  ) {
    final result = <FinanceTxn>[];
    for (final m in messages) {
      final txn = parse(sender: m.sender, body: m.body, date: m.date);
      if (txn != null) result.add(txn);
    }
    return inferRecurringSalary(result);
  }

  // A recurring credit smaller than this is treated as a refund/cashback/P2P,
  // not salary.
  static const _minRecurringSalary = 10000;
  // Same-size credits are bucketed to the nearest this many rupees so a small
  // month-to-month variance (variable pay, rounding) still groups together.
  static const _salaryBucketRupees = 500;

  /// Second pass: bank salary credits (NEFT/IMPS/RTGS/ACH) rarely contain a
  /// "salary" keyword, so [parse] tags them as ordinary credits. Detect them
  /// by structure instead — a same-size credit that recurs across two or more
  /// distinct months is almost certainly salary. Tags the single strongest
  /// such group (most months, then largest amount) as salary.
  static List<FinanceTxn> inferRecurringSalary(List<FinanceTxn> txns) {
    final buckets = <int, List<int>>{};
    for (var i = 0; i < txns.length; i++) {
      final t = txns[i];
      if (t.direction != TxnDirection.credit || t.isSalary) continue;
      if (t.amount < _minRecurringSalary) continue;
      final key = (t.amount / _salaryBucketRupees).round();
      (buckets[key] ??= <int>[]).add(i);
    }

    int? bestKey;
    var bestMonths = 1;
    var bestAmount = 0;
    buckets.forEach((key, indices) {
      final months = indices
          .map((i) => txns[i].date.year * 12 + txns[i].date.month)
          .toSet();
      if (months.length < 2) return; // not recurring
      final amount =
          indices.map((i) => txns[i].amount).reduce((a, b) => a > b ? a : b);
      if (months.length > bestMonths ||
          (months.length == bestMonths && amount > bestAmount)) {
        bestKey = key;
        bestMonths = months.length;
        bestAmount = amount;
      }
    });

    if (bestKey == null) return txns;
    final chosen = buckets[bestKey]!.toSet();
    return [
      for (var i = 0; i < txns.length; i++)
        chosen.contains(i) ? txns[i].copyWith(isSalary: true) : txns[i],
    ];
  }

  int? _extractAmount(String lowerBody) {
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
