import 'dart:convert';

import 'money_signal_models.dart';

/// Direction of a money movement parsed from an SMS/email.
enum TxnDirection { credit, debit }

/// Coarse spend categories inferred on-device from merchant/keyword hints.
/// Keep these stable — they are persisted and synced.
class SpendCategory {
  static const food = 'food';
  static const transport = 'transport';
  static const shopping = 'shopping';
  static const bills = 'bills';
  static const groceries = 'groceries';
  static const entertainment = 'entertainment';
  static const health = 'health';
  static const insurance = 'insurance';
  static const rent = 'rent';
  static const investment = 'investment';
  static const cash = 'cash';
  static const other = 'other';

  // Insurance sub-types
  static const insuranceCar = 'insurance:car';
  static const insuranceBike = 'insurance:bike';
  static const insuranceHealth = 'insurance:health';
  static const insuranceLife = 'insurance:life';
  static const insuranceOther = 'insurance:other';

  static const all = [
    food,
    transport,
    shopping,
    bills,
    groceries,
    entertainment,
    health,
    insurance,
    rent,
    investment,
    cash,
    other,
  ];

  /// Categories that count as non-discretionary living costs. Used to seed the
  /// savings-goal "essentials" figure without pulling in discretionary spend
  /// (shopping, entertainment, dining out).
  static const essentials = [
    rent,
    bills,
    groceries,
    transport,
    health,
    insurance,
  ];

  static String label(String category) {
    switch (category) {
      case food:
        return 'Food & dining';
      case transport:
        return 'Transport';
      case shopping:
        return 'Shopping';
      case bills:
        return 'Bills & recharge';
      case groceries:
        return 'Groceries';
      case entertainment:
        return 'Entertainment';
      case health:
        return 'Health';
      case insurance:
        return 'Insurance';
      case insuranceCar:
        return 'Car insurance';
      case insuranceBike:
        return 'Bike insurance';
      case insuranceHealth:
        return 'Health insurance';
      case insuranceLife:
        return 'Life insurance';
      case insuranceOther:
        return 'Other insurance';
      case rent:
        return 'Rent';
      case investment:
        return 'Investments';
      case cash:
        return 'Cash / ATM';
      default:
        return 'Other';
    }
  }
}

/// A single money movement parsed from one message.
class FinanceTxn {
  const FinanceTxn({
    required this.amount,
    required this.direction,
    required this.date,
    required this.category,
    required this.isSalary,
    this.merchant,
    this.sender,
    this.smsId,
    this.bodyPreview,
    this.categorySource = CategorySource.rules,
  });

  final int amount; // rupees, positive
  final TxnDirection direction;
  final DateTime date;
  final String category;
  final bool isSalary;
  final String? merchant;
  final String? sender;

  /// Android SMS `_id` of the source message, kept so the UI can offer to open
  /// the exact original SMS. Null when parsed from a source without an id.
  final int? smsId;

  /// Short excerpt of the original SMS body, retained so the user can identify
  /// a transaction in-app without leaving the screen. Truncated at parse time.
  final String? bodyPreview;

  /// How [category] was assigned — on-device rules, an AI fallback, or a manual
  /// user correction. Lets the UI show provenance and avoid re-sending
  /// user-corrected items to the AI.
  final CategorySource categorySource;

  FinanceTxn copyWith({
    String? category,
    bool? isSalary,
    String? merchant,
    CategorySource? categorySource,
  }) =>
      FinanceTxn(
        amount: amount,
        direction: direction,
        date: date,
        category: category ?? this.category,
        isSalary: isSalary ?? this.isSalary,
        merchant: merchant ?? this.merchant,
        sender: sender,
        smsId: smsId,
        bodyPreview: bodyPreview,
        categorySource: categorySource ?? this.categorySource,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'direction': direction.name,
        'date': date.toIso8601String(),
        'category': category,
        'isSalary': isSalary,
        if (merchant != null) 'merchant': merchant,
        if (sender != null) 'sender': sender,
        if (smsId != null) 'smsId': smsId,
        if (bodyPreview != null) 'bodyPreview': bodyPreview,
        'categorySource': categorySource.name,
      };

  factory FinanceTxn.fromJson(Map<String, dynamic> json) => FinanceTxn(
        amount: (json['amount'] as num?)?.round() ?? 0,
        direction: json['direction'] == 'credit'
            ? TxnDirection.credit
            : TxnDirection.debit,
        date: DateTime.tryParse(json['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        category: json['category']?.toString() ?? SpendCategory.other,
        isSalary: json['isSalary'] == true,
        merchant: json['merchant']?.toString(),
        sender: json['sender']?.toString(),
        smsId: (json['smsId'] as num?)?.toInt(),
        bodyPreview: json['bodyPreview']?.toString(),
        categorySource: CategorySource.fromName(
          json['categorySource']?.toString(),
        ),
      );
}

/// Provenance of a transaction's category.
enum CategorySource {
  rules,
  ai,
  manual;

  static CategorySource fromName(String? name) {
    switch (name) {
      case 'ai':
        return CategorySource.ai;
      case 'manual':
        return CategorySource.manual;
      default:
        return CategorySource.rules;
    }
  }
}

class MonthlySpendPoint {
  const MonthlySpendPoint({
    required this.month,
    required this.spent,
    required this.income,
  });

  final DateTime month;
  final int spent;
  final int income;
}

/// A category's latest-month spend compared with its prior-months average.
class CategoryTrend {
  const CategoryTrend({
    required this.category,
    required this.lastMonth,
    required this.priorAverage,
  });

  final String category;
  final int lastMonth;
  final int priorAverage;

  /// Signed change vs baseline (+0.3 = 30% higher than usual).
  double get changeRatio =>
      priorAverage <= 0 ? 0 : (lastMonth - priorAverage) / priorAverage;

  bool get isUp => lastMonth > priorAverage;

  /// Absolute rupee change, used to rank the biggest movers.
  int get changeMagnitude => (lastMonth - priorAverage).abs();
}

/// Aggregated spend/income picture built from parsed transactions.
/// Persisted locally and (best-effort) synced to the backend.
class SpendMap {
  const SpendMap({
    required this.txns,
    required this.windowStart,
    required this.windowEnd,
    required this.generatedAt,
    this.fallbackMonthlyIncome,
    this.otherMonthlyIncome = 0,
    this.manualPrimaryMonthlyIncome,
    this.manualMonthlySpend,
    this.trustedSalarySourceId,
    this.incomeSignal,
  });

  final List<FinanceTxn> txns;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime generatedAt;

  /// Take-home income (rupees/month) derived from a confirmed payslip / CTC,
  /// used only when no salary credit is detected in SMS. Transient — never
  /// persisted or synced (it is re-derived from live documents on read).
  final int? fallbackMonthlyIncome;

  /// Aggregate of user-entered "other income" sources (freelance, rent, side
  /// business, ...), see OtherIncomeNotifier. Transient — the individual
  /// sources/labels never leave the device; only this rupee total contributes
  /// to [monthlyIncome] so on-screen projections account for it.
  final int otherMonthlyIncome;

  /// User override for primary monthly income (salary). Local-only.
  final int? manualPrimaryMonthlyIncome;

  /// User override for average monthly spend. Local-only.
  final int? manualMonthlySpend;

  /// SMS sender selected by the user as the salary source to trust.
  /// Transient and local-only. Null keeps the legacy behavior of using every
  /// detected salary credit until the user makes a choice.
  final String? trustedSalarySourceId;

  /// Resolved income shared by Home, Spend map, Goal, and Tax. Transient and
  /// rebuilt from live sources whenever the map loads or those sources change.
  final IncomeSignal? incomeSignal;

  /// Returns a copy carrying [income] as the fallback monthly income.
  SpendMap withFallbackIncome(int? income) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: income,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        incomeSignal: null,
      );

  /// Returns a copy carrying [income] as the user-entered other-income total.
  SpendMap withOtherIncome(int income) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: income,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        incomeSignal: null,
      );

  SpendMap withAdjustments({
    int? manualPrimaryMonthlyIncome,
    int? manualMonthlySpend,
  }) =>
      SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        incomeSignal: null,
      );

  SpendMap withTrustedSalarySource(String? sourceId) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: sourceId,
        incomeSignal: null,
      );

  SpendMap withIncomeSignal(IncomeSignal signal) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        incomeSignal: signal,
      );

  static SpendMap empty(DateTime now) => SpendMap(
        txns: const [],
        windowStart: now,
        windowEnd: now,
        generatedAt: now,
      );

  bool get isEmpty => txns.isEmpty;

  /// Count of distinct calendar months (min 1) among the transactions matching
  /// [test]. This is the correct denominator for a monthly average: it reflects
  /// the months a given series actually has data for, instead of a fixed window
  /// or the raw first-to-last span (which over-counts empty months and mixes
  /// series that cover different months — see the income-vs-spend bug).
  int _distinctMonths(bool Function(FinanceTxn) test) {
    final months = <int>{};
    for (final t in txns) {
      if (test(t)) months.add(t.date.year * 12 + t.date.month);
    }
    return months.isEmpty ? 1 : months.length;
  }

  /// Distinct months that contain any transaction (for display only).
  int get observedMonths => _distinctMonths((_) => true);

  /// Distinct months containing a salary credit / any debit — each series is
  /// averaged over its own coverage so income and spend stay on the same
  /// per-month basis regardless of which months each happens to touch.
  int get _salaryMonths => _distinctMonths(isTrustedSalaryTransaction);
  int get _spendMonths =>
      _distinctMonths((t) => t.direction == TxnDirection.debit);

  int get totalSpent => txns
      .where((t) => t.direction == TxnDirection.debit)
      .fold(0, (sum, t) => sum + t.amount);

  bool isTrustedSalaryTransaction(FinanceTxn txn) {
    if (txn.direction != TxnDirection.credit || !txn.isSalary) return false;
    final trusted = trustedSalarySourceId;
    if (trusted == null || trusted.isEmpty) return true;
    return (txn.sender ?? '').trim().toUpperCase() == trusted;
  }

  List<FinanceTxn> get trustedSalaryTransactions =>
      txns.where(isTrustedSalaryTransaction).toList(growable: false);

  int get salaryCredited =>
      trustedSalaryTransactions.fold(0, (sum, t) => sum + t.amount);

  int get otherCredited => txns
      .where((t) => t.direction == TxnDirection.credit && !t.isSalary)
      .fold(0, (sum, t) => sum + t.amount);

  Map<String, int> get spendByCategory {
    final map = <String, int>{};
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  /// Categories sorted by amount, biggest first.
  List<MapEntry<String, int>> get topCategories {
    final entries = spendByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<MonthlySpendPoint> get monthlyTrend {
    final values = <String, MonthlySpendPoint>{};
    for (final txn in txns) {
      final month = DateTime(txn.date.year, txn.date.month);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final current =
          values[key] ?? MonthlySpendPoint(month: month, spent: 0, income: 0);
      values[key] = MonthlySpendPoint(
        month: month,
        spent: current.spent +
            (txn.direction == TxnDirection.debit ? txn.amount : 0),
        income:
            current.income + (isTrustedSalaryTransaction(txn) ? txn.amount : 0),
      );
    }
    final result = values.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  int get spendMonthsWithData => _spendMonths;
  int get salaryMonthsWithData => _salaryMonths;

  int get monthlySpend =>
      manualMonthlySpend ?? (totalSpent / _spendMonths).round();

  int get observedMonthlySpend => (totalSpent / _spendMonths).round();

  bool get spendIsManual =>
      manualMonthlySpend != null && manualMonthlySpend! > 0;

  /// Average monthly spend on non-discretionary categories only. Seeds the
  /// savings-goal "essentials" field without discretionary spend inflating it.
  int get monthlyEssentialSpend {
    final essentialTotal = txns
        .where((t) =>
            t.direction == TxnDirection.debit &&
            SpendCategory.essentials.contains(t.category))
        .fold<int>(0, (sum, t) => sum + t.amount);
    return (essentialTotal / _spendMonths).round();
  }

  /// True when income comes from a salary credit detected in SMS (as opposed to
  /// the payslip/CTC fallback). Lets the UI label the figure honestly.
  bool get incomeIsDetected =>
      incomeSignal?.source == IncomeSignalSource.salarySms ||
      (incomeSignal == null && !primaryIncomeIsManual && salaryCredited > 0);

  int get observedPrimaryMonthlyIncome {
    if (salaryCredited > 0) return (salaryCredited / _salaryMonths).round();
    return fallbackMonthlyIncome ?? 0;
  }

  int get primaryMonthlyIncome =>
      incomeSignal?.primaryMonthlyIncome ??
      manualPrimaryMonthlyIncome ??
      observedPrimaryMonthlyIncome;

  bool get primaryIncomeIsManual =>
      incomeSignal?.source == IncomeSignalSource.edited ||
      (incomeSignal == null &&
          manualPrimaryMonthlyIncome != null &&
          manualPrimaryMonthlyIncome! > 0);

  String get primaryIncomeSourceLabel {
    if (incomeSignal != null) return incomeSignal!.source.label;
    if (primaryIncomeIsManual) return 'Your entered figure';
    if (salaryCredited > 0) return 'Salary SMS average';
    if (fallbackMonthlyIncome != null && fallbackMonthlyIncome! > 0) {
      return 'Payslip estimate';
    }
    return 'Not set';
  }

  /// Total monthly income used everywhere on screen: primary (SMS salary or
  /// payslip/CTC fallback) plus any user-entered other-income total.
  int get monthlyIncome =>
      incomeSignal?.monthlyIncome ?? primaryMonthlyIncome + otherMonthlyIncome;

  /// True when other-income has been added, so the UI can break the total
  /// down instead of presenting one opaque number.
  bool get hasOtherIncome => otherMonthlyIncome > 0;

  /// Signed monthly balance = income − spend. Positive means saving, negative
  /// means overspending. Unlike [realisticMonthlySavings] this is NOT floored,
  /// so the UI can honestly show a shortfall instead of collapsing it to zero.
  /// Returns 0 when income is unknown (nothing meaningful to compare against).
  int get monthlyNet {
    if (monthlyIncome <= 0) return 0;
    return monthlyIncome - monthlySpend;
  }

  /// True when observed spend exceeds income for the month.
  bool get isOverspending => monthlyIncome > 0 && monthlyNet < 0;

  /// Monthly shortfall (rupees) when overspending, else 0. The "waste" figure.
  int get monthlyWaste => isOverspending ? -monthlyNet : 0;

  /// True when income is a payslip/CTC estimate rather than a detected salary
  /// credit AND we also have SMS spend — i.e. the net mixes two sources and
  /// should be shown with a caveat.
  bool get netMixesSources =>
      !primaryIncomeIsManual && !incomeIsDetected && totalSpent > 0;

  /// What can realistically be saved each month = income − observed spend,
  /// floored at 0. When no salary detected, falls back to 0 (unknown).
  int get realisticMonthlySavings {
    if (monthlyIncome <= 0) return 0;
    final diff = monthlyIncome - monthlySpend;
    return diff < 0 ? 0 : diff;
  }

  double get savingsRate {
    if (monthlyIncome <= 0) return 0;
    return realisticMonthlySavings / monthlyIncome;
  }

  /// Same as [realisticMonthlySavings] but computed from [primaryMonthlyIncome]
  /// only. Used exclusively for the backend sync payload so that user-entered
  /// other income — local-only and never transmitted — cannot influence any
  /// number that reaches the server, even indirectly through a derived figure.
  int get realisticMonthlySavingsExcludingOtherIncome {
    if (primaryMonthlyIncome <= 0) return 0;
    final diff = primaryMonthlyIncome - monthlySpend;
    return diff < 0 ? 0 : diff;
  }

  /// Observed-income savings for server sync — ignores manual income/spend
  /// overrides and other-income totals.
  int get observedRealisticMonthlySavings {
    if (observedPrimaryMonthlyIncome <= 0) return 0;
    final diff = observedPrimaryMonthlyIncome - observedMonthlySpend;
    return diff < 0 ? 0 : diff;
  }

  // ---- Forecasting -------------------------------------------------------
  // Predictive figures derived from the SMS time-series. These stay meaningful
  // even when absolute capture is incomplete, because they compare the current
  // month's pace against the user's own recent history rather than to a fixed
  // "correct" total.

  int _monthKey(DateTime d) => d.year * 12 + d.month;

  /// Spend recorded so far in the reference (latest) month of the window.
  int get currentMonthSpend {
    final key = _monthKey(windowEnd);
    return txns
        .where((t) =>
            t.direction == TxnDirection.debit && _monthKey(t.date) == key)
        .fold(0, (sum, t) => sum + t.amount);
  }

  /// Projected total spend for the current month, extrapolating the run-rate so
  /// far to the full month (days elapsed → days in month). Falls back to the
  /// historical monthly average when the current month has no data yet.
  int get projectedMonthlySpend {
    final spentSoFar = currentMonthSpend;
    if (spentSoFar <= 0) return monthlySpend;
    final day = windowEnd.day;
    final daysInMonth = DateTime(windowEnd.year, windowEnd.month + 1, 0).day;
    if (day <= 0 || day >= daysInMonth) return spentSoFar;
    return (spentSoFar / day * daysInMonth).round();
  }

  /// Projected month-end spend vs the historical monthly average, as a signed
  /// ratio (+0.2 = on pace to spend 20% more than usual). 0 when no baseline.
  double get spendPaceVsAverage {
    final avg = monthlySpend;
    if (avg <= 0) return 0;
    return (projectedMonthlySpend - avg) / avg;
  }

  /// Monthly spend per category, oldest→newest, as a map of category → list of
  /// (monthKey, amount). Used to derive per-category trends.
  Map<String, Map<int, int>> get _monthlyByCategory {
    final out = <String, Map<int, int>>{};
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      final byMonth = out[t.category] ??= <int, int>{};
      final key = _monthKey(t.date);
      byMonth[key] = (byMonth[key] ?? 0) + t.amount;
    }
    return out;
  }

  /// Per-category trend: latest month's spend vs the average of prior months.
  /// Only categories with at least two months of data and a non-zero baseline
  /// are returned, sorted by the size of the change (biggest movers first).
  List<CategoryTrend> get categoryTrends {
    final trends = <CategoryTrend>[];
    _monthlyByCategory.forEach((category, byMonth) {
      if (byMonth.length < 2) return;
      final months = byMonth.keys.toList()..sort();
      final lastKey = months.last;
      final last = byMonth[lastKey]!;
      final priorKeys = months.sublist(0, months.length - 1);
      final priorAvg =
          priorKeys.fold<int>(0, (s, k) => s + byMonth[k]!) / priorKeys.length;
      if (priorAvg <= 0) return;
      trends.add(CategoryTrend(
        category: category,
        lastMonth: last,
        priorAverage: priorAvg.round(),
      ));
    });
    trends.sort((a, b) => b.changeMagnitude.compareTo(a.changeMagnitude));
    return trends;
  }

  Map<String, dynamic> toJson() => {
        'txns': txns.map((t) => t.toJson()).toList(),
        'windowStart': windowStart.toIso8601String(),
        'windowEnd': windowEnd.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory SpendMap.fromJson(Map<String, dynamic> json) {
    final rawTxns = (json['txns'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FinanceTxn.fromJson)
        .toList();
    final now = DateTime.now();
    return SpendMap(
      txns: rawTxns,
      windowStart:
          DateTime.tryParse(json['windowStart']?.toString() ?? '') ?? now,
      windowEnd: DateTime.tryParse(json['windowEnd']?.toString() ?? '') ?? now,
      generatedAt:
          DateTime.tryParse(json['generatedAt']?.toString() ?? '') ?? now,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  static SpendMap fromJsonString(String s) =>
      SpendMap.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
