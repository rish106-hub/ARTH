class MoneyGoal {
  const MoneyGoal({
    required this.id,
    required this.name,
    required this.category,
    required this.targetAmount,
    required this.currentAmount,
    required this.targetDate,
    required this.monthlyEssentials,
    required this.monthlyFamilySupport,
  });

  final String id;
  final String name;
  final String category;
  final int targetAmount;
  final int currentAmount;
  final DateTime targetDate;
  final int monthlyEssentials;
  final int monthlyFamilySupport;

  factory MoneyGoal.fromJson(Map<String, dynamic> json) => MoneyGoal(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Money goal',
        category: json['category']?.toString() ?? 'other',
        targetAmount: (json['targetAmount'] as num?)?.round() ?? 0,
        currentAmount: (json['currentAmount'] as num?)?.round() ?? 0,
        targetDate: DateTime.tryParse(json['targetDate']?.toString() ?? '') ??
            DateTime.now().add(const Duration(days: 365)),
        monthlyEssentials: (json['monthlyEssentials'] as num?)?.round() ?? 0,
        monthlyFamilySupport:
            (json['monthlyFamilySupport'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'category': category,
        'targetAmount': targetAmount,
        'currentAmount': currentAmount,
        'targetDate': targetDate.toIso8601String().split('T').first,
        'monthlyEssentials': monthlyEssentials,
        'monthlyFamilySupport': monthlyFamilySupport,
      };
}

class GoalProjection {
  const GoalProjection({
    required this.monthsRemaining,
    required this.amountRemaining,
    required this.requiredMonthly,
    required this.availableMonthly,
    required this.monthlyHeadroom,
  });

  final int monthsRemaining;
  final int amountRemaining;
  final int requiredMonthly;
  final int availableMonthly;
  final int monthlyHeadroom;

  bool get isFeasible => monthlyHeadroom >= 0;
}

GoalProjection projectGoal({
  required MoneyGoal goal,
  required int monthlyNetPay,
  DateTime? asOf,
}) {
  final now = asOf ?? DateTime.now();
  final monthDifference = (goal.targetDate.year - now.year) * 12 +
      goal.targetDate.month -
      now.month;
  final months = monthDifference.clamp(1, 600);
  final remaining =
      (goal.targetAmount - goal.currentAmount).clamp(0, 1000000000);
  final requiredMonthly = remaining == 0 ? 0 : (remaining / months).ceil();
  final available =
      (monthlyNetPay - goal.monthlyEssentials - goal.monthlyFamilySupport)
          .clamp(0, 1000000000);
  return GoalProjection(
    monthsRemaining: months,
    amountRemaining: remaining,
    requiredMonthly: requiredMonthly,
    availableMonthly: available,
    monthlyHeadroom: available - requiredMonthly,
  );
}
