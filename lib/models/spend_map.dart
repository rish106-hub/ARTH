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
    this.source = 'sms',
  });

  final int amount; // rupees, positive
  final TxnDirection direction;
  final DateTime date;
  final String category;
  final bool isSalary;
  final String? merchant;
  final String? sender;
  final String source; // 'sms' | 'email'

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'direction': direction.name,
        'date': date.toIso8601String(),
        'category': category,
        'isSalary': isSalary,
        'source': source,
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
        source: json['source']?.toString() ?? 'sms',
      );
}

/// Aggregated spend/income picture built from parsed transactions.
/// Persisted locally and (best-effort) synced to the backend.
class SpendMap {
  const SpendMap({
    required this.txns,
    required this.windowStart,
    required this.windowEnd,
    required this.generatedAt,
  });

  final List<FinanceTxn> txns;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime generatedAt;

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

  int get monthlySpend => (totalSpent / monthsSpan).round();
  int get monthlyIncome => (salaryCredited / monthsSpan).round();

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
