import 'package:arth/models/spend_map.dart';
import 'package:arth/models/spend_scan_period_copy.dart';
import 'package:arth/providers/spend_map_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpendMap sampleMap({
    int salary = 54000,
    int spend = 12000,
    int? manualIncome,
    int? manualSpend,
  }) {
    final now = DateTime(2026, 7, 28);
    return SpendMap(
      txns: [
        FinanceTxn(
          amount: salary,
          direction: TxnDirection.credit,
          date: DateTime(2026, 7, 1),
          category: 'other',
          isSalary: true,
        ),
        FinanceTxn(
          amount: spend,
          direction: TxnDirection.debit,
          date: DateTime(2026, 7, 5),
          category: SpendCategory.food,
          isSalary: false,
        ),
      ],
      windowStart: DateTime(2026, 4, 1),
      windowEnd: now,
      generatedAt: now,
      manualPrimaryMonthlyIncome: manualIncome,
      manualMonthlySpend: manualSpend,
    );
  }

  test('manual primary income overrides SMS average', () {
    final map = sampleMap(manualIncome: 60000);
    expect(map.observedPrimaryMonthlyIncome, 54000);
    expect(map.primaryMonthlyIncome, 60000);
    expect(map.primaryIncomeIsManual, isTrue);
    expect(map.primaryIncomeSourceLabel, 'Your entered figure');
  });

  test('manual monthly spend overrides SMS trend average', () {
    final map = sampleMap(manualSpend: 15000);
    expect(map.observedMonthlySpend, 12000);
    expect(map.monthlySpend, 15000);
    expect(map.spendIsManual, isTrue);
  });

  group('SpendScanPeriodCopy', () {
    test('titles stay compact because scan scope is shown separately', () {
      expect(SpendScanPeriod.threeMonths.avgMonthlySpendTitle, 'Monthly spend');
      expect(
          SpendScanPeriod.yearToDate.avgMonthlyIncomeTitle, 'Monthly income');
    });

    test('spend caption keeps the source and coverage compact', () {
      final caption = SpendScanPeriod.sixMonths.spendTrendCaption(
        monthsWithSpend: 4,
        totalTransactions: 42,
      );
      expect(caption, '42 SMS · 4 mo.');
    });
  });

  test('observedRealisticMonthlySavings ignores manual overrides for sync', () {
    final map = sampleMap(manualIncome: 90000, manualSpend: 5000);
    expect(map.realisticMonthlySavingsExcludingOtherIncome, greaterThan(50000));
    expect(map.observedRealisticMonthlySavings, lessThan(54000));
  });
}
