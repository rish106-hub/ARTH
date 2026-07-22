import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class MoneyPlan {
  final int annualFixedPay;
  final int annualVariablePay;
  final int annualEquityPay;
  final int monthlyTakeHome;
  final int monthlyCommitments;
  final int monthlyInvesting;
  final int liquidSavings;
  final String primaryGoalName;
  final int primaryGoalTarget;
  final int primaryGoalSaved;

  const MoneyPlan({
    this.annualFixedPay = 0,
    this.annualVariablePay = 0,
    this.annualEquityPay = 0,
    this.monthlyTakeHome = 0,
    this.monthlyCommitments = 0,
    this.monthlyInvesting = 0,
    this.liquidSavings = 0,
    this.primaryGoalName = '',
    this.primaryGoalTarget = 0,
    this.primaryGoalSaved = 0,
  });

  int get totalCompensation =>
      annualFixedPay + annualVariablePay + annualEquityPay;

  bool get isComplete => annualFixedPay > 0 && monthlyTakeHome > 0;

  MoneyPlan copyWith({
    int? annualFixedPay,
    int? annualVariablePay,
    int? annualEquityPay,
    int? monthlyTakeHome,
    int? monthlyCommitments,
    int? monthlyInvesting,
    int? liquidSavings,
    String? primaryGoalName,
    int? primaryGoalTarget,
    int? primaryGoalSaved,
  }) {
    return MoneyPlan(
      annualFixedPay: annualFixedPay ?? this.annualFixedPay,
      annualVariablePay: annualVariablePay ?? this.annualVariablePay,
      annualEquityPay: annualEquityPay ?? this.annualEquityPay,
      monthlyTakeHome: monthlyTakeHome ?? this.monthlyTakeHome,
      monthlyCommitments: monthlyCommitments ?? this.monthlyCommitments,
      monthlyInvesting: monthlyInvesting ?? this.monthlyInvesting,
      liquidSavings: liquidSavings ?? this.liquidSavings,
      primaryGoalName: primaryGoalName ?? this.primaryGoalName,
      primaryGoalTarget: primaryGoalTarget ?? this.primaryGoalTarget,
      primaryGoalSaved: primaryGoalSaved ?? this.primaryGoalSaved,
    );
  }

  Map<String, dynamic> toJson() => {
        'annualFixedPay': annualFixedPay,
        'annualVariablePay': annualVariablePay,
        'annualEquityPay': annualEquityPay,
        'monthlyTakeHome': monthlyTakeHome,
        'monthlyCommitments': monthlyCommitments,
        'monthlyInvesting': monthlyInvesting,
        'liquidSavings': liquidSavings,
        'primaryGoalName': primaryGoalName,
        'primaryGoalTarget': primaryGoalTarget,
        'primaryGoalSaved': primaryGoalSaved,
      };

  factory MoneyPlan.fromJson(Map<String, dynamic> json) {
    int amount(String key) =>
        ((json[key] as num?)?.round() ?? 0).clamp(0, 1000000000);
    return MoneyPlan(
      annualFixedPay: amount('annualFixedPay'),
      annualVariablePay: amount('annualVariablePay'),
      annualEquityPay: amount('annualEquityPay'),
      monthlyTakeHome: amount('monthlyTakeHome'),
      monthlyCommitments: amount('monthlyCommitments'),
      monthlyInvesting: amount('monthlyInvesting'),
      liquidSavings: amount('liquidSavings'),
      primaryGoalName: (json['primaryGoalName'] as String? ?? '').trim(),
      primaryGoalTarget: amount('primaryGoalTarget'),
      primaryGoalSaved: amount('primaryGoalSaved'),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory MoneyPlan.fromJsonString(String source) =>
      MoneyPlan.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

@immutable
class MoneySnapshot {
  final MoneyPlan plan;

  const MoneySnapshot(this.plan);

  int get availableThisMonth =>
      (plan.monthlyTakeHome - plan.monthlyCommitments - plan.monthlyInvesting)
          .clamp(0, 1000000000);

  int get monthlyOutflow => plan.monthlyCommitments + plan.monthlyInvesting;

  double get committedRatio => plan.monthlyTakeHome == 0
      ? 0
      : (plan.monthlyCommitments / plan.monthlyTakeHome).clamp(0, 1);

  double get investingRatio => plan.monthlyTakeHome == 0
      ? 0
      : (plan.monthlyInvesting / plan.monthlyTakeHome).clamp(0, 1);

  double get emergencyRunwayMonths => plan.monthlyCommitments == 0
      ? 0
      : plan.liquidSavings / plan.monthlyCommitments;

  double get goalProgress => plan.primaryGoalTarget == 0
      ? 0
      : (plan.primaryGoalSaved / plan.primaryGoalTarget).clamp(0, 1);
}

enum MoneyDecisionKind {
  setup,
  cashBuffer,
  commitments,
  goal,
  taxCheck,
  review
}

@immutable
class MoneyDecision {
  final MoneyDecisionKind kind;
  final String title;
  final String body;
  final String actionLabel;
  final String route;

  const MoneyDecision({
    required this.kind,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.route,
  });
}

MoneyDecision nextMoneyDecision(
  MoneyPlan plan, {
  required bool taxProfileComplete,
}) {
  if (!plan.isComplete) {
    return const MoneyDecision(
      kind: MoneyDecisionKind.setup,
      title: 'Build your money baseline',
      body: 'Add income, commitments and liquid savings.',
      actionLabel: 'Set up my plan',
      route: '/money-setup',
    );
  }

  final snapshot = MoneySnapshot(plan);
  if (snapshot.committedRatio > 0.65) {
    return const MoneyDecision(
      kind: MoneyDecisionKind.commitments,
      title: 'Your fixed commitments are heavy',
      body: 'More than 65% of take-home is already committed each month.',
      actionLabel: 'Review allocation',
      route: '/plan',
    );
  }
  if (snapshot.emergencyRunwayMonths < 3) {
    final months = snapshot.emergencyRunwayMonths.toStringAsFixed(1);
    return MoneyDecision(
      kind: MoneyDecisionKind.cashBuffer,
      title: 'Build more financial runway',
      body:
          'Liquid savings currently cover about $months months of commitments.',
      actionLabel: 'Review cash buffer',
      route: '/plan',
    );
  }
  if (plan.primaryGoalTarget > 0 && snapshot.goalProgress < 1) {
    return MoneyDecision(
      kind: MoneyDecisionKind.goal,
      title: 'Move your primary goal forward',
      body:
          '${(snapshot.goalProgress * 100).round()}% of ${plan.primaryGoalName} is funded.',
      actionLabel: 'Open goal plan',
      route: '/plan',
    );
  }
  if (!taxProfileComplete) {
    return const MoneyDecision(
      kind: MoneyDecisionKind.taxCheck,
      title: 'Add the tax layer',
      body: 'Map your tax position to improve the annual income forecast.',
      actionLabel: 'Run tax check',
      route: '/questions',
    );
  }
  return const MoneyDecision(
    kind: MoneyDecisionKind.review,
    title: 'Your baseline is in order',
    body: 'Review the plan when income or commitments change.',
    actionLabel: 'Review plan',
    route: '/plan',
  );
}
