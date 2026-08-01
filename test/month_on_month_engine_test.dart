import 'package:arth/features/month_on_month/engine/month_on_month_engine.dart';
import 'package:arth/models/spend_map.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceTxn _txn({
  required int amount,
  required DateTime date,
  TxnDirection direction = TxnDirection.debit,
  String category = SpendCategory.food,
  bool isSalary = false,
  bool isInternalTransfer = false,
}) {
  return FinanceTxn(
    amount: amount,
    direction: direction,
    date: date,
    category: category,
    isSalary: isSalary,
    isInternalTransfer: isInternalTransfer,
  );
}

SpendMap _map(List<FinanceTxn> txns) => SpendMap(
      txns: txns,
      windowStart: DateTime(2026, 5),
      windowEnd: DateTime(2026, 7, 31),
      generatedAt: DateTime(2026, 7, 31),
    );

void main() {
  group('month on month', () {
    test('each month carries the one before it, newest first', () {
      final map = _map([
        _txn(amount: 1000, date: DateTime(2026, 5, 4)),
        _txn(amount: 1500, date: DateTime(2026, 6, 4)),
        _txn(amount: 900, date: DateTime(2026, 7, 4)),
      ]);

      final months = MonthOnMonthEngine.compare(map);

      expect(months.first.month, DateTime(2026, 7));
      expect(months.first.spent, 900);
      expect(months.first.previousSpent, 1500);
      expect(months.first.spentChange, -600);
      expect(months.first.spentMore, isFalse);
      expect(months.last.month, DateTime(2026, 5));
    });

    test('the earliest month has no previous month, not a zero one', () {
      final map = _map([_txn(amount: 1000, date: DateTime(2026, 5, 4))]);

      final earliest = MonthOnMonthEngine.compare(map).last;

      expect(earliest.previousSpent, isNull);
      expect(earliest.spentChange, isNull);
      // A first month must not read as infinite growth.
      expect(earliest.spentChangeRatio, isNull);
    });

    test('a jump from zero is not reported as a percentage', () {
      final map = _map([
        _txn(
          amount: 60000,
          date: DateTime(2026, 6, 1),
          direction: TxnDirection.credit,
          isSalary: true,
          category: SpendCategory.other,
        ),
        _txn(amount: 500, date: DateTime(2026, 5, 4)),
        _txn(amount: 500, date: DateTime(2026, 6, 4)),
      ]);

      final june = MonthOnMonthEngine.compare(map).first;

      expect(june.income, 60000);
      expect(june.previousIncome, 0);
      expect(june.incomeChange, 60000);
      expect(june.incomeChangeRatio, isNull);
    });

    test('internal transfers stay out of both sides', () {
      final map = _map([
        _txn(amount: 1000, date: DateTime(2026, 6, 4)),
        _txn(
          amount: 25000,
          date: DateTime(2026, 6, 5),
          isInternalTransfer: true,
        ),
        _txn(amount: 1000, date: DateTime(2026, 7, 4)),
      ]);

      final months = MonthOnMonthEngine.compare(map);

      expect(months.firstWhere((m) => m.month.month == 6).spent, 1000);
    });
  });

  group('movers', () {
    test('ranked by rupees, not by ratio', () {
      final map = _map([
        // Doubles, but only by ₹40.
        _txn(
            amount: 40,
            date: DateTime(2026, 6, 2),
            category: SpendCategory.food),
        _txn(
            amount: 80,
            date: DateTime(2026, 7, 2),
            category: SpendCategory.food),
        // Up by ₹9,000, a much smaller ratio.
        _txn(
          amount: 30000,
          date: DateTime(2026, 6, 3),
          category: SpendCategory.bills,
        ),
        _txn(
          amount: 39000,
          date: DateTime(2026, 7, 3),
          category: SpendCategory.bills,
        ),
      ]);

      final movers = MonthOnMonthEngine.movers(map);

      expect(movers.first.category, SpendCategory.bills);
      expect(movers.first.change, 9000);
      expect(movers.first.isUp, isTrue);
    });

    test('a single month has nothing to compare', () {
      final map = _map([_txn(amount: 100, date: DateTime(2026, 7, 2))]);
      expect(MonthOnMonthEngine.movers(map), isEmpty);
    });

    test('categories that did not move are left out', () {
      final map = _map([
        _txn(amount: 500, date: DateTime(2026, 6, 2)),
        _txn(amount: 500, date: DateTime(2026, 7, 2)),
      ]);
      expect(MonthOnMonthEngine.movers(map), isEmpty);
    });
  });
}
