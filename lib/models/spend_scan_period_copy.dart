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

  /// The selected analysis window is already visible above the tiles, so their
  /// labels stay short enough to scan side by side.
  String get avgMonthlyIncomeTitle => 'Monthly income';

  /// Title for the spend stat tile.
  String get avgMonthlySpendTitle => 'Monthly spend';

  /// Explains how spend was derived from SMS in the selected window.
  String spendTrendCaption({
    required int monthsWithSpend,
    required int totalTransactions,
  }) {
    if (totalTransactions == 0) return 'No spend SMS yet.';
    return '$totalTransactions SMS · $monthsWithSpend mo.';
  }

  /// Explains how income was derived (SMS, payslip, or manual).
  String incomeTrendCaption({
    required String sourceLabel,
    required int monthsWithSalary,
    required bool includesOtherIncome,
    required bool isManual,
  }) {
    if (isManual) return 'You set this figure.';
    if (sourceLabel == 'Salary SMS average') {
      return includesOtherIncome
          ? 'Salary SMS + other income'
          : 'Salary SMS · $monthsWithSalary mo.';
    }
    if (sourceLabel == 'Payslip estimate') {
      return includesOtherIncome
          ? 'Payslip + other income'
          : 'Confirmed payslip';
    }
    return 'Tap to add income.';
  }
}
