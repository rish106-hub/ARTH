import 'package:arth/models/money_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goal projection separates essentials and family support', () {
    final projection = projectGoal(
      goal: MoneyGoal(
        id: 'goal-1',
        name: 'Support parents',
        category: 'family',
        targetAmount: 240000,
        currentAmount: 60000,
        targetDate: DateTime(2027, 7, 1),
        monthlyEssentials: 18000,
        monthlyFamilySupport: 5000,
      ),
      monthlyNetPay: 38567,
      asOf: DateTime(2026, 7, 22),
    );

    expect(projection.monthsRemaining, 12);
    expect(projection.amountRemaining, 180000);
    expect(projection.requiredMonthly, 15000);
    expect(projection.availableMonthly, 15567);
    expect(projection.monthlyHeadroom, 567);
    expect(projection.isFeasible, isTrue);
  });

  test('goal projection reports a monthly shortfall', () {
    final projection = projectGoal(
      goal: MoneyGoal(
        id: '',
        name: 'Emergency fund',
        category: 'safety',
        targetAmount: 300000,
        currentAmount: 0,
        targetDate: DateTime(2027, 1, 1),
        monthlyEssentials: 25000,
        monthlyFamilySupport: 5000,
      ),
      monthlyNetPay: 40000,
      asOf: DateTime(2026, 7, 22),
    );

    expect(projection.requiredMonthly, 50000);
    expect(projection.availableMonthly, 10000);
    expect(projection.monthlyHeadroom, -40000);
    expect(projection.isFeasible, isFalse);
  });
}
