import '../../../models/spend_map.dart';

String normalizeSalarySource(String? sender) =>
    (sender ?? '').trim().toUpperCase();

class SalarySourceSummary {
  const SalarySourceSummary({
    required this.id,
    required this.latestAmount,
    required this.months,
  });

  final String id;
  final int latestAmount;
  final int months;
}

enum RecurringKind {
  rent,
  sip,
  subscription,
  repeat;

  String get label => switch (this) {
        RecurringKind.rent => 'Rent',
        RecurringKind.sip => 'SIP',
        RecurringKind.subscription => 'Subscription',
        RecurringKind.repeat => 'Repeat payment',
      };
}

class RecurringSpend {
  const RecurringSpend({
    required this.id,
    required this.label,
    required this.kind,
    required this.typicalAmount,
    required this.occurrences,
    required this.nextExpectedDate,
    required this.highConfidence,
  });

  final String id;
  final String label;
  final RecurringKind kind;
  final int typicalAmount;
  final int occurrences;
  final DateTime nextExpectedDate;
  final bool highConfidence;
}

class CategoryBudgetSuggestion {
  const CategoryBudgetSuggestion({
    required this.category,
    required this.historicalMonthlyAverage,
    required this.suggestedLimit,
    required this.currentMonthSpend,
    required this.projectedMonthSpend,
  });

  final String category;
  final int historicalMonthlyAverage;
  final int suggestedLimit;
  final int currentMonthSpend;
  final int projectedMonthSpend;
}

class SpendCompletenessEngine {
  const SpendCompletenessEngine._();

  static List<SalarySourceSummary> salarySources(SpendMap map) {
    final salaries = map.txns.where(
      (txn) =>
          txn.direction == TxnDirection.credit &&
          txn.isSalary &&
          normalizeSalarySource(txn.sender).isNotEmpty,
    );
    final grouped = <String, List<FinanceTxn>>{};
    for (final txn in salaries) {
      grouped.putIfAbsent(normalizeSalarySource(txn.sender), () => []).add(txn);
    }
    final result = <SalarySourceSummary>[];
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => b.date.compareTo(a.date));
      final months = entry.value
          .map((txn) => txn.date.year * 12 + txn.date.month)
          .toSet()
          .length;
      result.add(
        SalarySourceSummary(
          id: entry.key,
          latestAmount: entry.value.first.amount,
          months: months,
        ),
      );
    }
    result.sort((a, b) => b.latestAmount.compareTo(a.latestAmount));
    return result;
  }

  static List<RecurringSpend> recurringSpend(SpendMap map) {
    final debits = map.txns
        .where((txn) => txn.direction == TxnDirection.debit)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final groups = <String, List<List<FinanceTxn>>>{};
    for (final txn in debits) {
      final identity = _recurringIdentity(txn);
      final clusters = groups.putIfAbsent(identity, () => []);
      List<FinanceTxn>? match;
      for (final cluster in clusters) {
        final average = cluster.fold<int>(0, (sum, item) => sum + item.amount) /
            cluster.length;
        final tolerance = (average * 0.10).round().clamp(100, 100000000);
        if ((txn.amount - average).abs() <= tolerance) {
          match = cluster;
          break;
        }
      }
      if (match == null) {
        clusters.add([txn]);
      } else {
        match.add(txn);
      }
    }

    final result = <RecurringSpend>[];
    for (final clusters in groups.values) {
      for (final cluster in clusters) {
        final monthly = <int, FinanceTxn>{};
        for (final txn in cluster) {
          monthly[txn.date.year * 12 + txn.date.month] = txn;
        }
        final occurrences = monthly.values.toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        if (occurrences.length < 2) continue;
        final gaps = <int>[];
        for (var i = 1; i < occurrences.length; i++) {
          gaps.add(
            occurrences[i].date.difference(occurrences[i - 1].date).inDays,
          );
        }
        final averageGap =
            gaps.fold<int>(0, (sum, gap) => sum + gap) / gaps.length;
        if (averageGap < 20 || averageGap > 48) continue;

        final representative = occurrences.last;
        final kind = _kindFor(representative);
        final typicalAmount =
            (occurrences.fold<int>(0, (sum, txn) => sum + txn.amount) /
                    occurrences.length)
                .round();
        final source = _recurringIdentity(representative);
        final id =
            '${kind.name}-${_safeId(source)}-${(typicalAmount / 100).round()}';
        result.add(
          RecurringSpend(
            id: id,
            label: _recurringLabel(representative, kind),
            kind: kind,
            typicalAmount: typicalAmount,
            occurrences: occurrences.length,
            nextExpectedDate: occurrences.last.date.add(
              Duration(days: averageGap.round()),
            ),
            highConfidence: occurrences.length >= 3,
          ),
        );
      }
    }
    result.sort((a, b) {
      final confidence = b.highConfidence ? 1 : 0;
      final otherConfidence = a.highConfidence ? 1 : 0;
      if (confidence != otherConfidence) {
        return confidence.compareTo(otherConfidence);
      }
      return b.typicalAmount.compareTo(a.typicalAmount);
    });
    return result;
  }

  static List<CategoryBudgetSuggestion> budgetSuggestions(SpendMap map) {
    final monthlyTotals = <String, Map<int, int>>{};
    final allSpendMonths = <int>{};
    for (final txn in map.txns.where(
      (txn) => txn.direction == TxnDirection.debit,
    )) {
      final month = txn.date.year * 12 + txn.date.month;
      allSpendMonths.add(month);
      final category = monthlyTotals.putIfAbsent(txn.category, () => {});
      category[month] = (category[month] ?? 0) + txn.amount;
    }
    if (allSpendMonths.isEmpty) return const [];
    final currentMonth = map.windowEnd.year * 12 + map.windowEnd.month;
    final result = <CategoryBudgetSuggestion>[];
    for (final entry in monthlyTotals.entries) {
      final total = entry.value.values.fold<int>(
        0,
        (sum, amount) => sum + amount,
      );
      final average = (total / allSpendMonths.length).round();
      if (average <= 0) continue;
      final currentSpend = entry.value[currentMonth] ?? 0;
      final daysInMonth = DateTime(
        map.windowEnd.year,
        map.windowEnd.month + 1,
        0,
      ).day;
      final projected = currentSpend <= 0 || map.windowEnd.day >= daysInMonth
          ? currentSpend
          : (currentSpend / map.windowEnd.day * daysInMonth).round();
      result.add(
        CategoryBudgetSuggestion(
          category: entry.key,
          historicalMonthlyAverage: average,
          suggestedLimit: ((average + 99) ~/ 100) * 100,
          currentMonthSpend: currentSpend,
          projectedMonthSpend: projected,
        ),
      );
    }
    result.sort(
      (a, b) =>
          b.historicalMonthlyAverage.compareTo(a.historicalMonthlyAverage),
    );
    return result;
  }

  static String _recurringIdentity(FinanceTxn txn) {
    final merchant = txn.merchant?.trim().toLowerCase();
    if (merchant != null && merchant.isNotEmpty) {
      return '${txn.category}|$merchant';
    }
    return '${txn.category}|${normalizeSalarySource(txn.sender)}';
  }

  static RecurringKind _kindFor(FinanceTxn txn) {
    if (txn.category == SpendCategory.rent) return RecurringKind.rent;
    if (txn.category == SpendCategory.investment) return RecurringKind.sip;
    final text = '${txn.merchant ?? ''} ${txn.bodyPreview ?? ''}'.toLowerCase();
    const subscriptionWords = [
      'netflix',
      'spotify',
      'prime',
      'hotstar',
      'subscription',
      'renewal',
      'autopay',
    ];
    if (subscriptionWords.any(text.contains)) {
      return RecurringKind.subscription;
    }
    return RecurringKind.repeat;
  }

  static String _recurringLabel(FinanceTxn txn, RecurringKind kind) {
    final merchant = txn.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    return kind.label;
  }

  static String _safeId(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
