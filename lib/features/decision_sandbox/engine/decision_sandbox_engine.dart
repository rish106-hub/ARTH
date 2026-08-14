import '../../../models/money_goal.dart';
import '../models/decision_sandbox_models.dart';

class DecisionProjection {
  const DecisionProjection({
    required this.monthlyRoomChange,
    required this.projectedTrackedRoom,
    required this.commitmentChange,
    required this.monthsToAbsorbOneOffCost,
    this.goalFinishChangeMonths,
  });

  final int monthlyRoomChange;
  final int projectedTrackedRoom;
  final int commitmentChange;
  final int? monthsToAbsorbOneOffCost;
  final int? goalFinishChangeMonths;
}

class DecisionSandboxEngine {
  const DecisionSandboxEngine._();

  static DecisionProjection project({
    required DecisionScenario scenario,
    required int trackedMonthlyRoom,
    MoneyGoal? goal,
    int? monthlyIncome,
  }) {
    final roomChange = scenario.monthlyRoomChange;
    final projectedRoom = trackedMonthlyRoom + roomChange;
    final absorbMonths = scenario.oneOffCost <= 0 || projectedRoom <= 0
        ? null
        : (scenario.oneOffCost / projectedRoom).ceil();
    return DecisionProjection(
      monthlyRoomChange: roomChange,
      projectedTrackedRoom: projectedRoom,
      commitmentChange: scenario.monthlyCostChange,
      monthsToAbsorbOneOffCost: absorbMonths,
      goalFinishChangeMonths: _goalFinishChange(
        goal: goal,
        monthlyIncome: monthlyIncome,
        scenario: scenario,
      ),
    );
  }

  static int? _goalFinishChange({
    required MoneyGoal? goal,
    required int? monthlyIncome,
    required DecisionScenario scenario,
  }) {
    if (goal == null || monthlyIncome == null || monthlyIncome <= 0) {
      return null;
    }
    final remaining =
        (goal.targetAmount - goal.currentAmount).clamp(0, 1000000000);
    if (remaining == 0) {
      return 0;
    }
    final before =
        (monthlyIncome - goal.monthlyEssentials - goal.monthlyFamilySupport)
            .clamp(0, 1000000000);
    final after = (monthlyIncome +
            scenario.monthlyIncomeChange -
            goal.monthlyEssentials -
            goal.monthlyFamilySupport -
            scenario.monthlyCostChange)
        .clamp(0, 1000000000);
    if (before <= 0 || after <= 0) {
      return null;
    }
    return (remaining / after).ceil() - (remaining / before).ceil();
  }
}
