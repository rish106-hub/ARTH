import 'package:flutter_test/flutter_test.dart';

import 'package:arth/models/spend_map.dart';

FinanceTxn _debit(int amount, DateTime date, String category) => FinanceTxn(
      amount: amount,
      direction: TxnDirection.debit,
      date: date,
      category: category,
      isSalary: false,
    );

void main() {
  group('projectedMonthlySpend', () {
    test('extrapolates the current month run-rate to full month', () {
      final map = SpendMap(
        txns: [
          _debit(1000, DateTime(2026, 7, 5), SpendCategory.food),
        ],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 10), // 10 of 31 days elapsed
        generatedAt: DateTime(2026, 7, 10),
      );
      // 1000 / 10 * 31 = 3100.
      expect(map.projectedMonthlySpend, 3100);
      expect(map.spendPaceVsAverage > 0, isTrue);
    });

    test('falls back to the monthly average when current month is empty', () {
      final map = SpendMap(
        txns: [
          _debit(2000, DateTime(2026, 6, 5), SpendCategory.food),
        ],
        windowStart: DateTime(2026, 6, 1),
        windowEnd: DateTime(2026, 7, 15),
        generatedAt: DateTime(2026, 7, 15),
      );
      expect(map.currentMonthSpend, 0);
      expect(map.projectedMonthlySpend, map.monthlySpend);
    });
  });

  group('categoryTrends', () {
    test('ranks biggest movers first with correct direction', () {
      final map = SpendMap(
        txns: [
          _debit(1000, DateTime(2026, 6, 3), SpendCategory.food),
          _debit(3000, DateTime(2026, 7, 3), SpendCategory.food),
          _debit(500, DateTime(2026, 6, 8), SpendCategory.transport),
          _debit(400, DateTime(2026, 7, 8), SpendCategory.transport),
        ],
        windowStart: DateTime(2026, 6, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      final trends = map.categoryTrends;
      expect(trends.first.category, SpendCategory.food);
      expect(trends.first.isUp, isTrue);
      final transport =
          trends.firstWhere((t) => t.category == SpendCategory.transport);
      expect(transport.isUp, isFalse);
    });

    test('ignores categories with only one month of data', () {
      final map = SpendMap(
        txns: [
          _debit(1000, DateTime(2026, 7, 3), SpendCategory.food),
        ],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      expect(map.categoryTrends, isEmpty);
    });
  });
}
