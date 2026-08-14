import 'package:arth/features/monthly_commitments/engine/monthly_commitments_engine.dart';
import 'package:arth/features/monthly_commitments/models/monthly_commitment_models.dart';
import 'package:arth/features/spend_completeness/engine/spend_completeness_engine.dart';
import 'package:arth/features/spend_completeness/models/spend_completeness_models.dart';
import 'package:arth/models/spend_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceTxn debit(int amount, int month) => FinanceTxn(
        amount: amount,
        direction: TxnDirection.debit,
        date: DateTime(2026, month, 2),
        category: SpendCategory.rent,
        isSalary: false,
        merchant: 'Landlord',
      );

  test('uses confirmed recurring items and manual commitments only', () {
    final map = SpendMap(
      txns: [debit(20000, 5), debit(20000, 6), debit(20000, 7)],
      windowStart: DateTime(2026, 5, 1),
      windowEnd: DateTime(2026, 7, 28),
      generatedAt: DateTime(2026, 7, 28),
    );
    final recurringId = SpendCompletenessEngine.recurringSpend(map).single.id;
    final items = MonthlyCommitmentsEngine.resolve(
      map: map,
      settings: SpendCompletenessState(confirmedRecurringIds: {recurringId}),
      saved: MonthlyCommitmentsState(manual: [
        MonthlyCommitment(
          id: 'manual-family',
          label: 'Family support',
          monthlyAmount: 5000,
          nextExpectedDate: DateTime(2026, 7, 5),
          source: CommitmentSource.manual,
        ),
      ]),
    );

    expect(items.map((item) => item.label),
        containsAll(['Landlord', 'Family support']));
    expect(MonthlyCommitmentsEngine.total(items), 25000);
  });
}
