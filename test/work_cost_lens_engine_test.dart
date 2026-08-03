import 'package:arth/features/work_costs/engine/work_cost_lens_engine.dart';
import 'package:arth/models/spend_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceTxn debit({
    required int amount,
    required DateTime date,
    required String merchant,
    String category = SpendCategory.food,
    bool lowDetailCardBill = false,
  }) =>
      FinanceTxn(
        amount: amount,
        direction: TxnDirection.debit,
        date: date,
        category: category,
        isSalary: false,
        merchant: merchant,
        isLowDetailCardBill: lowDetailCardBill,
      );

  SpendMap map(List<FinanceTxn> transactions) => SpendMap(
        txns: transactions,
        windowStart: DateTime(2026, 5, 1),
        windowEnd: DateTime(2026, 7, 28),
        generatedAt: DateTime(2026, 7, 28),
      );

  test('finds repeat identifiable merchant costs without assigning meaning',
      () {
    final candidates = WorkCostLensEngine.candidates(map([
      debit(amount: 120, date: DateTime(2026, 5, 2), merchant: 'Campus Cafe'),
      debit(amount: 140, date: DateTime(2026, 6, 4), merchant: 'Campus Cafe'),
      debit(amount: 160, date: DateTime(2026, 7, 6), merchant: 'Campus Cafe'),
      debit(amount: 700, date: DateTime(2026, 7, 8), merchant: 'One-off store'),
    ]));

    expect(candidates, hasLength(1));
    final cafe = candidates.single;
    expect(cafe.merchant, 'Campus Cafe');
    expect(cafe.transactionCount, 3);
    expect(cafe.observedMonths, 3);
    expect(cafe.monthlyAmount, 140);
    expect(cafe.medianTransactionAmount, 140);
    expect(cafe.oneLessPerWeekSavings, 607);
  });

  test('requires three purchases and ignores opaque card-bill totals', () {
    final candidates = WorkCostLensEngine.candidates(map([
      debit(amount: 200, date: DateTime(2026, 6, 2), merchant: 'Metro'),
      debit(amount: 200, date: DateTime(2026, 7, 2), merchant: 'Metro'),
      debit(
        amount: 12000,
        date: DateTime(2026, 5, 20),
        merchant: 'Card bill',
        lowDetailCardBill: true,
      ),
      debit(
        amount: 12000,
        date: DateTime(2026, 6, 20),
        merchant: 'Card bill',
        lowDetailCardBill: true,
      ),
      debit(
        amount: 12000,
        date: DateTime(2026, 7, 20),
        merchant: 'Card bill',
        lowDetailCardBill: true,
      ),
    ]));

    expect(candidates, isEmpty);
  });

  test('uses the merchant and category for a stable candidate identity', () {
    final candidates = WorkCostLensEngine.candidates(map([
      for (var month = 5; month <= 7; month++)
        debit(
          amount: 250,
          date: DateTime(2026, month, 10),
          merchant: 'Quick Ride',
          category: SpendCategory.transport,
        ),
    ]));

    expect(candidates.single.id, 'work_cost_transport_quick_ride');
  });
}
