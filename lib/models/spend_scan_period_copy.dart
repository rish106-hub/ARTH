import '../providers/spend_map_provider.dart';

/// User-facing copy tied to the SMS analysis window. Keeps income/spend labels
/// honest about what period is being averaged.
extension SpendScanPeriodCopy on SpendScanPeriod {
  String get windowPhrase => switch (this) {
        SpendScanPeriod.oneMonth => 'last 1 month',
        SpendScanPeriod.threeMonths => 'last 3 months',
        SpendScanPeriod.sixMonths => 'last 6 months',
        SpendScanPeriod.twelveMonths => 'last 12 months',
        SpendScanPeriod.yearToDate => 'year to date',
      };

  String get pickerLabel => switch (this) {
        SpendScanPeriod.oneMonth => '1 month',
        SpendScanPeriod.threeMonths => '3 months',
        SpendScanPeriod.sixMonths => '6 months',
        SpendScanPeriod.twelveMonths => '12 months',
        SpendScanPeriod.yearToDate => 'YTD',
      };

  /// Title for the income stat tile, e.g. "Avg monthly income (last 3 months)".
  String get avgMonthlyIncomeTitle => 'Avg monthly income ($windowPhrase)';

  /// Title for the spend stat tile.
  String get avgMonthlySpendTitle => 'Avg monthly spend ($windowPhrase)';

  /// Explains how spend was derived from SMS in the selected window.
  String spendTrendCaption({
    required int monthsWithSpend,
    required int totalTransactions,
  }) {
    final monthWord = monthsWithSpend == 1 ? 'month' : 'months';
    return 'Trend from bank/UPI SMS in the $windowPhrase — '
        '${monthsWithSpend == 0 ? 'no spend months yet' : 'averaged across $monthsWithSpend $monthWord with spend'} '
        '($totalTransactions transaction${totalTransactions == 1 ? '' : 's'}).';
  }

  /// Explains how income was derived (SMS, payslip, or manual).
  String incomeTrendCaption({
    required String sourceLabel,
    required int monthsWithSalary,
    required bool includesOtherIncome,
    required bool isManual,
  }) {
    if (isManual) {
      return 'You set this figure. It replaces the SMS/payslip estimate for the '
          '$windowPhrase view.';
    }
    if (sourceLabel == 'Salary SMS average') {
      final monthWord = monthsWithSalary == 1 ? 'month' : 'months';
      return 'Salary credits in the $windowPhrase, averaged across '
          '$monthsWithSalary $monthWord with a detected credit.'
          '${includesOtherIncome ? ' Other income is added on top.' : ''}';
    }
    if (sourceLabel == 'Payslip estimate') {
      return 'No salary credit in SMS for the $windowPhrase — using your '
          'confirmed payslip/CTC as a monthly estimate.'
          '${includesOtherIncome ? ' Other income is added on top.' : ''}';
    }
    return 'Tap to add or correct your monthly income for the $windowPhrase view.';
  }
}
