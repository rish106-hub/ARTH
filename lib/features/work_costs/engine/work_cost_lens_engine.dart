import '../../../models/spend_map.dart';
import '../models/work_cost_models.dart';

/// Finds repeat merchant patterns that a user may choose to mark as work costs.
///
/// This engine does not guess whether a merchant is an office canteen, commute,
/// or social spend. It only groups identifiable repeat purchases and leaves the
/// meaning to the user.
class WorkCostLensEngine {
  const WorkCostLensEngine._();

  static const minimumCandidateTransactions = 3;

  static List<WorkCostCandidate> candidates(SpendMap map) {
    final groups = <String, List<FinanceTxn>>{};
    for (final transaction in map.txns) {
      if (!transaction.countsAsSpend || transaction.isLowDetailCardBill) {
        continue;
      }
      final merchant = _normalizedMerchant(transaction.merchant);
      if (merchant == null) continue;
      final id = '${transaction.category}|$merchant';
      groups.putIfAbsent(id, () => []).add(transaction);
    }

    final result = <WorkCostCandidate>[];
    for (final entry in groups.entries) {
      final transactions = entry.value;
      if (transactions.length < minimumCandidateTransactions) continue;
      final amounts = transactions.map((item) => item.amount).toList()..sort();
      final total = amounts.fold<int>(0, (sum, amount) => sum + amount);
      final observedMonths = {
        for (final transaction in transactions)
          transaction.date.year * 12 + transaction.date.month,
      }.length;
      final representative = transactions.first;
      result.add(
        WorkCostCandidate(
          id: _candidateId(representative.category, representative.merchant!),
          merchant: representative.merchant!.trim(),
          category: representative.category,
          transactionCount: transactions.length,
          observedMonths: observedMonths,
          totalAmount: total,
          monthlyAmount: (total / observedMonths).round(),
          medianTransactionAmount: _median(amounts),
        ),
      );
    }
    result.sort((a, b) {
      final amount = b.monthlyAmount.compareTo(a.monthlyAmount);
      return amount != 0
          ? amount
          : b.transactionCount.compareTo(a.transactionCount);
    });
    return result;
  }

  static String? _normalizedMerchant(String? merchant) {
    final value = merchant?.trim();
    if (value == null || value.isEmpty) return null;
    return value.toLowerCase();
  }

  static String _candidateId(String category, String merchant) {
    final raw = '${category}_$merchant'.toLowerCase();
    final slug = raw
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'work_cost_${slug.substring(0, slug.length.clamp(0, 60))}';
  }

  static int _median(List<int> sortedAmounts) {
    final middle = sortedAmounts.length ~/ 2;
    if (sortedAmounts.length.isOdd) return sortedAmounts[middle];
    return ((sortedAmounts[middle - 1] + sortedAmounts[middle]) / 2).round();
  }
}
