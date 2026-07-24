import 'dart:convert';

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
  static const rent = 'rent';
  static const investment = 'investment';
  static const cash = 'cash';
  static const other = 'other';

  static const all = [
    food,
    transport,
    shopping,
    bills,
    groceries,
    entertainment,
    health,
    rent,
    investment,
    cash,
    other,
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
  });

  final int amount; // rupees, positive
  final TxnDirection direction;
  final DateTime date;
  final String category;
  final bool isSalary;
  final String? merchant;
  final String? sender;

  FinanceTxn copyWith({String? category, bool? isSalary}) => FinanceTxn(
        amount: amount,
        direction: direction,
        date: date,
        category: category ?? this.category,
        isSalary: isSalary ?? this.isSalary,
        merchant: merchant,
        sender: sender,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'direction': direction.name,
        'date': date.toIso8601String(),
        'category': category,
        'isSalary': isSalary,
        if (merchant != null) 'merchant': merchant,
        if (sender != null) 'sender': sender,
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
      );
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

/// Aggregated spend/income picture built from parsed transactions.
/// Persisted locally and (best-effort) synced to the backend.
class SpendMap {
  const SpendMap({
    required this.txns,
    required this.windowStart,
    required this.windowEnd,
    required this.generatedAt,
    this.fallbackMonthlyIncome,
  });

  final List<FinanceTxn> txns;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime generatedAt;

  /// Take-home income (rupees/month) derived from a confirmed payslip / CTC,
  /// used only when no salary credit is detected in SMS. Transient — never
  /// persisted or synced (it is re-derived from live documents on read).
  final int? fallbackMonthlyIncome;

  /// Returns a copy carrying [income] as the fallback monthly income.
  SpendMap withFallbackIncome(int? income) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: income,
      );

  static SpendMap empty(DateTime now) => SpendMap(
        txns: const [],
        windowStart: now,
        windowEnd: now,
        generatedAt: now,
      );

  bool get isEmpty => txns.isEmpty;

  /// Number of whole months the window spans (min 1).
  int get monthsSpan {
    final diff = (windowEnd.year - windowStart.year) * 12 +
        windowEnd.month -
        windowStart.month;
    return diff < 1 ? 1 : diff + 1;
  }

  int get totalSpent => txns
      .where((t) => t.direction == TxnDirection.debit)
      .fold(0, (sum, t) => sum + t.amount);

  int get salaryCredited => txns
      .where((t) => t.direction == TxnDirection.credit && t.isSalary)
      .fold(0, (sum, t) => sum + t.amount);

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
        income: current.income +
            (txn.direction == TxnDirection.credit && txn.isSalary
                ? txn.amount
                : 0),
      );
    }
    final result = values.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  int get monthlySpend => (totalSpent / monthsSpan).round();

  /// Monthly income. Prefers salary credits detected in SMS; when none are
  /// found, falls back to payslip/CTC-derived income so income never collapses
  /// to zero for a user with a confirmed payslip but no salary-credit SMS.
  int get monthlyIncome {
    final fromSalary = (salaryCredited / monthsSpan).round();
    if (fromSalary > 0) return fromSalary;
    return fallbackMonthlyIncome ?? 0;
  }

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
