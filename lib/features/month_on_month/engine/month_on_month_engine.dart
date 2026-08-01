import '../../../models/spend_map.dart';

/// One month set against the one before it.
///
/// [previousSpent] and [previousIncome] are null for the earliest month in the
/// window, which is the honest answer — there is nothing to compare it with.
/// Callers must not treat a missing previous month as zero, or the first month
/// always reads as infinite growth.
class MonthComparison {
  const MonthComparison({
    required this.month,
    required this.spent,
    required this.income,
    this.previousSpent,
    this.previousIncome,
  });

  final DateTime month;
  final int spent;
  final int income;
  final int? previousSpent;
  final int? previousIncome;

  /// Income minus spend. Signed, so a shortfall stays visible as one.
  int get net => income - spent;

  int? get spentChange => previousSpent == null ? null : spent - previousSpent!;

  int? get incomeChange =>
      previousIncome == null ? null : income - previousIncome!;

  /// Change as a fraction of the previous month. Null when there is no previous
  /// month, and null when the previous month was zero — a jump from nothing is
  /// not a percentage, and rendering one would be a divide-by-zero dressed up.
  double? get spentChangeRatio {
    final previous = previousSpent;
    if (previous == null || previous == 0) return null;
    return (spent - previous) / previous;
  }

  double? get incomeChangeRatio {
    final previous = previousIncome;
    if (previous == null || previous == 0) return null;
    return (income - previous) / previous;
  }

  bool get spentMore => spentChange != null && spentChange! > 0;
}

/// A category's spend in one month against the month before.
class CategoryMonthMove {
  const CategoryMonthMove({
    required this.category,
    required this.amount,
    required this.previousAmount,
  });

  final String category;
  final int amount;
  final int previousAmount;

  int get change => amount - previousAmount;
  bool get isUp => change > 0;
  int get magnitude => change.abs();
}

class MonthOnMonthEngine {
  const MonthOnMonthEngine._();

  /// Months in the window, newest first, each carrying the month before it.
  ///
  /// Built from [SpendMap.monthlyTrend] so spend and income mean exactly what
  /// they mean everywhere else — in particular income counts only trusted
  /// salary, and spend routes through `countsAsSpend`, so internal transfers
  /// stay out of both.
  static List<MonthComparison> compare(SpendMap map) {
    final points = map.monthlyTrend;
    final result = <MonthComparison>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final previous = i == 0 ? null : points[i - 1];
      result.add(
        MonthComparison(
          month: point.month,
          spent: point.spent,
          income: point.income,
          previousSpent: previous?.spent,
          previousIncome: previous?.income,
        ),
      );
    }
    return result.reversed.toList(growable: false);
  }

  /// Categories that moved most between the two most recent months, biggest
  /// absolute change first. Empty when the window holds fewer than two months.
  ///
  /// Ranked by rupees rather than percent: a category doubling from ₹40 to ₹80
  /// is not news, and one rising ₹9,000 is, however small the ratio.
  static List<CategoryMonthMove> movers(SpendMap map, {int limit = 5}) {
    final months = <DateTime>{
      for (final txn in map.txns.where((t) => t.countsAsSpend))
        DateTime(txn.date.year, txn.date.month),
    }.toList()
      ..sort();
    if (months.length < 2) return const [];

    final latest = months.last;
    final previous = months[months.length - 2];

    final byCategory = <String, ({int latest, int previous})>{};
    for (final txn in map.txns.where((t) => t.countsAsSpend)) {
      final month = DateTime(txn.date.year, txn.date.month);
      final isLatest = month == latest;
      final isPrevious = month == previous;
      if (!isLatest && !isPrevious) continue;
      final held = byCategory[txn.category] ?? (latest: 0, previous: 0);
      byCategory[txn.category] = (
        latest: held.latest + (isLatest ? txn.amount : 0),
        previous: held.previous + (isPrevious ? txn.amount : 0),
      );
    }

    final moves = [
      for (final entry in byCategory.entries)
        CategoryMonthMove(
          category: entry.key,
          amount: entry.value.latest,
          previousAmount: entry.value.previous,
        ),
    ]..sort((a, b) => b.magnitude.compareTo(a.magnitude));

    return moves
        .where((move) => move.change != 0)
        .take(limit)
        .toList(growable: false);
  }
}
