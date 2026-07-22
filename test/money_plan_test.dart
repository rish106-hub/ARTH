import 'package:arth/models/money_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plan = MoneyPlan(
    annualFixedPay: 3000000,
    annualVariablePay: 300000,
    annualEquityPay: 600000,
    monthlyTakeHome: 180000,
    monthlyCommitments: 70000,
    monthlyInvesting: 40000,
    liquidSavings: 500000,
    primaryGoalName: 'Home deposit',
    primaryGoalTarget: 2000000,
    primaryGoalSaved: 500000,
  );

  test('money snapshot uses take-home and explicit monthly allocations', () {
    const snapshot = MoneySnapshot(plan);

    expect(plan.totalCompensation, 3900000);
    expect(snapshot.availableThisMonth, 70000);
    expect(snapshot.monthlyOutflow, 110000);
    expect(snapshot.emergencyRunwayMonths, closeTo(7.14, 0.01));
    expect(snapshot.goalProgress, 0.25);
  });

  test('money plan round-trips through local JSON', () {
    final restored = MoneyPlan.fromJsonString(plan.toJsonString());

    expect(restored.totalCompensation, plan.totalCompensation);
    expect(restored.monthlyTakeHome, plan.monthlyTakeHome);
    expect(restored.primaryGoalName, 'Home deposit');
  });

  test('next decision prioritizes financial safety before tax', () {
    const lowBuffer = MoneyPlan(
      annualFixedPay: 3000000,
      monthlyTakeHome: 180000,
      monthlyCommitments: 90000,
      monthlyInvesting: 30000,
      liquidSavings: 100000,
    );

    final decision = nextMoneyDecision(
      lowBuffer,
      taxProfileComplete: false,
    );

    expect(decision.kind, MoneyDecisionKind.cashBuffer);
    expect(decision.route, '/plan');
  });

  test('tax check appears only after baseline safety and goals are in order',
      () {
    const stable = MoneyPlan(
      annualFixedPay: 3000000,
      monthlyTakeHome: 180000,
      monthlyCommitments: 60000,
      monthlyInvesting: 40000,
      liquidSavings: 500000,
    );

    final decision = nextMoneyDecision(
      stable,
      taxProfileComplete: false,
    );

    expect(decision.kind, MoneyDecisionKind.taxCheck);
    expect(decision.route, '/questions');
  });
}
