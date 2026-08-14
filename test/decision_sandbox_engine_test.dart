import 'package:arth/features/decision_sandbox/engine/decision_sandbox_engine.dart';
import 'package:arth/features/decision_sandbox/models/decision_sandbox_models.dart';
import 'package:arth/models/money_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scenario = DecisionScenario(
    id: 'move',
    name: 'Move closer',
    kind: DecisionKind.moveForWork,
    monthlyIncomeChange: 0,
    currentMonthlyCost: 7000,
    proposedMonthlyCost: 12000,
    oneOffCost: 30000,
    createdAt: DateTime(2026, 8, 3),
  );

  test('shows cost delta and one-off absorption without affordability claim',
      () {
    final result = DecisionSandboxEngine.project(
      scenario: scenario,
      trackedMonthlyRoom: 15000,
    );
    expect(result.monthlyRoomChange, -5000);
    expect(result.projectedTrackedRoom, 10000);
    expect(result.commitmentChange, 5000);
    expect(result.monthsToAbsorbOneOffCost, 3);
  });

  test('shows optional goal finish impact only with valid goal income', () {
    final goal = MoneyGoal(
      id: 'goal',
      name: 'Emergency fund',
      category: 'cash',
      targetAmount: 120000,
      currentAmount: 0,
      targetDate: DateTime(2027, 8, 1),
      monthlyEssentials: 20000,
      monthlyFamilySupport: 0,
    );
    final result = DecisionSandboxEngine.project(
      scenario: scenario,
      trackedMonthlyRoom: 15000,
      goal: goal,
      monthlyIncome: 50000,
    );
    expect(result.goalFinishChangeMonths, 1);
  });
}
