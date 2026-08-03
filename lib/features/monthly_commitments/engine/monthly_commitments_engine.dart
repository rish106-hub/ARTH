import '../../../features/spend_completeness/engine/spend_completeness_engine.dart';
import '../../../features/spend_completeness/models/spend_completeness_models.dart';
import '../../../models/spend_map.dart';
import '../models/monthly_commitment_models.dart';

class MonthlyCommitmentsEngine {
  const MonthlyCommitmentsEngine._();

  static List<MonthlyCommitment> resolve({
    required SpendMap map,
    required SpendCompletenessState settings,
    required MonthlyCommitmentsState saved,
  }) {
    final detected = SpendCompletenessEngine.recurringSpend(map)
        .where((item) => settings.confirmedRecurringIds.contains(item.id))
        .map(
          (item) => MonthlyCommitment(
            id: 'detected:${item.id}',
            label: item.label,
            monthlyAmount: item.typicalAmount,
            nextExpectedDate: item.nextExpectedDate,
            source: CommitmentSource.detected,
          ),
        );
    final result = [...detected, ...saved.manual]
      ..sort((a, b) => a.nextExpectedDate.compareTo(b.nextExpectedDate));
    return result;
  }

  static int total(List<MonthlyCommitment> items) =>
      items.fold(0, (sum, item) => sum + item.monthlyAmount);
}
