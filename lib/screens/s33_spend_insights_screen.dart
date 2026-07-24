import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/spend_map.dart';
import '../providers/spend_map_provider.dart';
import '../theme/paycheck_theme.dart';
import '../utils/money_format.dart';

class SpendInsightsScreen extends ConsumerWidget {
  const SpendInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendMapProvider);
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        elevation: 0,
        foregroundColor: PaycheckColors.ink,
        title: Text('Spend map', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ARTH reads only bank & UPI transaction SMS on this phone to map where your money goes. Personal messages are ignored and parsing stays on-device.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 20),
              _PeriodPicker(
                selected: state.selectedPeriod,
                onSelected: (period) =>
                    ref.read(spendMapProvider.notifier).selectPeriod(period),
              ),
              const SizedBox(height: 20),
              if (state.loading)
                const _Loading()
              else if (state.permissionDenied)
                _PermissionCard(
                    onRetry: () => ref.read(spendMapProvider.notifier).scan())
              else if (state.error != null)
                _ErrorCard(
                  message: state.error!,
                  onRetry: () => ref.read(spendMapProvider.notifier).scan(),
                )
              else if (!state.hasData)
                _EmptyCard(
                  period: state.selectedPeriod,
                  onScan: () => ref.read(spendMapProvider.notifier).scan(),
                )
              else
                _Insights(map: state.map!),
              if (state.hasData && !state.loading) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => ref.read(spendMapProvider.notifier).scan(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rescan SMS'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading & categorising your SMS…'),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onScan, required this.period});
  final VoidCallback onScan;
  final SpendScanPeriod period;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 32, color: PaycheckColors.contract),
          const SizedBox(height: 12),
          Text('Build your spend map', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'We will scan ${period.label.toLowerCase()} of bank and UPI SMS, detect salary credits and spends, and estimate what you can realistically save.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PaycheckColors.ink,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onScan,
              child: const Text('Scan my SMS'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sms_failed_outlined,
              size: 32, color: PaycheckColors.claim),
          const SizedBox(height: 12),
          Text('SMS access needed', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'ARTH needs permission to read SMS to build your spend map. Nothing leaves your phone during parsing. Grant it in the prompt, or enable it in Settings › Apps › ARTH › Permissions.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Could not scan', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(message,
              style: PaycheckType.body(color: PaycheckColors.inkSoft)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final SpendScanPeriod selected;
  final ValueChanged<SpendScanPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SMS HISTORY', style: PaycheckType.utility()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SpendScanPeriod.values.map((period) {
            return ChoiceChip(
              label: Text(period.label),
              selected: selected == period,
              onSelected: (_) => onSelected(period),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 7),
        Text(
          '3 months recommended for a useful recent baseline.',
          style: PaycheckType.utility(color: PaycheckColors.contract),
        ),
      ],
    );
  }
}

class _Insights extends ConsumerWidget {
  const _Insights({required this.map});
  final SpendMap map;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unclear = map.txns.indexed
        .where(
          (entry) =>
              entry.$2.direction == TxnDirection.debit &&
              entry.$2.category == SpendCategory.other,
        )
        .take(3)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SavingsHero(map: map),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Monthly income',
                value: money0(map.monthlyIncome),
                color: PaycheckColors.contract,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Monthly spend',
                value: money0(map.monthlySpend),
                color: PaycheckColors.claim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Where it goes', style: PaycheckType.heading()),
        const SizedBox(height: 12),
        _CategoryPie(map: map),
        const SizedBox(height: 16),
        _CategoryBars(map: map),
        const SizedBox(height: 24),
        Text('Month by month', style: PaycheckType.heading()),
        const SizedBox(height: 4),
        Text(
          'Spend per month',
          style: PaycheckType.utility(color: PaycheckColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _MonthlyTrend(map: map),
        if (unclear.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${unclear.length} unclear transaction${unclear.length == 1 ? '' : 's'}',
                  style: PaycheckType.heading(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Review only these items. Everything else is already categorized.',
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _reviewUnclear(context, ref, unclear),
                  icon: const Icon(Icons.rule_folder_outlined),
                  label: const Text('Review categories'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/money-goal'),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Build a savings plan'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${map.txns.length} transactions across ${map.observedMonths} month(s), '
          'ending ${DateFormat('d MMM').format(map.windowEnd)}.',
          style: PaycheckType.utility(),
        ),
      ],
    );
  }
}

Future<void> _reviewUnclear(
  BuildContext context,
  WidgetRef ref,
  List<(int, FinanceTxn)> unclear,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Review categories', style: PaycheckType.title()),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...unclear.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.$2.merchant ?? entry.$2.sender ?? 'Unknown merchant',
                    style: PaycheckType.bodyStrong(),
                  ),
                  Text(
                    '${money0(entry.$2.amount)} · ${DateFormat('d MMM').format(entry.$2.date)}',
                    style: PaycheckType.utility(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: SpendCategory.all
                        .where((category) => category != SpendCategory.other)
                        .map(
                          (category) => ActionChip(
                            label: Text(SpendCategory.label(category)),
                            onPressed: () async {
                              await ref
                                  .read(spendMapProvider.notifier)
                                  .recategorize(entry.$1, category);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CategoryPie extends StatelessWidget {
  const _CategoryPie({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final entries = map.topCategories;
    if (entries.isEmpty) return const SizedBox.shrink();
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 118,
            child: CustomPaint(painter: _SpendPiePainter(entries)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.take(5).map((entry) {
                final share =
                    map.totalSpent == 0 ? 0 : entry.value / map.totalSpent;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${SpendCategory.label(entry.key)} ${(share * 100).round()}%',
                    style: PaycheckType.utility(),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendPiePainter extends CustomPainter {
  const _SpendPiePainter(this.entries);

  final List<MapEntry<String, int>> entries;
  static const colors = [
    PaycheckColors.contract,
    PaycheckColors.claim,
    PaycheckColors.matched,
    PaycheckColors.pending,
    Color(0xFF64748B),
    Color(0xFF7C3AED),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total <= 0) return;
    var start = -1.5708;
    final rect = Offset.zero & size;
    for (var index = 0; index < entries.length; index++) {
      final sweep = entries[index].value / total * 6.28319;
      canvas.drawArc(
        rect.deflate(8),
        start,
        sweep,
        true,
        Paint()..color = colors[index % colors.length],
      );
      start += sweep;
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * 0.22,
      Paint()..color = PaycheckColors.paper,
    );
  }

  @override
  bool shouldRepaint(covariant _SpendPiePainter oldDelegate) =>
      oldDelegate.entries != entries;
}

class _MonthlyTrend extends StatelessWidget {
  const _MonthlyTrend({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final points = map.monthlyTrend;
    if (points.isEmpty) {
      return Text(
        'No monthly trend available.',
        style: PaycheckType.body(color: PaycheckColors.inkSoft),
      );
    }
    final max = points.fold<int>(
      1,
      (value, point) => point.spent > value ? point.spent : value,
    );
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: points.map((point) {
            final height = 112 * point.spent / max;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      money0(point.spent),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: PaycheckType.utility(),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: height.clamp(4, 112),
                      decoration: const BoxDecoration(
                        color: PaycheckColors.claim,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('MMM').format(point.month),
                      style: PaycheckType.utility(),
                    ),
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _SavingsHero extends StatelessWidget {
  const _SavingsHero({required this.map});
  final SpendMap map;
  @override
  Widget build(BuildContext context) {
    final savings = map.realisticMonthlySavings;
    final rate = (map.savingsRate * 100).round();
    final coaching = _coachingLine(map);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PaycheckColors.matchedSoft,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: PaycheckColors.matched.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REALISTIC MONTHLY SAVINGS',
              style: PaycheckType.utility(color: PaycheckColors.matched)),
          const SizedBox(height: 6),
          Text(money0(savings),
              style: PaycheckType.display(color: PaycheckColors.ink)),
          if (map.monthlyIncome > 0)
            Text(
              map.incomeIsDetected
                  ? '$rate% of detected income'
                  : '$rate% of estimated income (from your payslip)',
              style: PaycheckType.utility(),
            ),
          const SizedBox(height: 10),
          Text(coaching, style: PaycheckType.body()),
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.map});
  final SpendMap map;
  @override
  Widget build(BuildContext context) {
    final categories = map.topCategories;
    if (categories.isEmpty) {
      return Text('No spends detected yet.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft));
    }
    final max = categories.first.value;
    return Column(
      children: [
        for (final entry in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(_iconFor(entry.key),
                    size: 20, color: PaycheckColors.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(SpendCategory.label(entry.key),
                                style: PaycheckType.bodyStrong()),
                          ),
                          Text(money0(entry.value),
                              style: PaycheckType.bodyStrong()),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : entry.value / max,
                          minHeight: 8,
                          backgroundColor: PaycheckColors.line,
                          color: PaycheckColors.claim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: PaycheckType.utility(color: color)),
          const SizedBox(height: 6),
          Text(value, style: PaycheckType.title()),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PaycheckColors.line),
      ),
      child: child,
    );
  }
}

IconData _iconFor(String category) {
  switch (category) {
    case SpendCategory.food:
      return Icons.restaurant_outlined;
    case SpendCategory.groceries:
      return Icons.local_grocery_store_outlined;
    case SpendCategory.transport:
      return Icons.directions_car_outlined;
    case SpendCategory.shopping:
      return Icons.shopping_bag_outlined;
    case SpendCategory.entertainment:
      return Icons.movie_outlined;
    case SpendCategory.bills:
      return Icons.receipt_outlined;
    case SpendCategory.health:
      return Icons.medical_services_outlined;
    case SpendCategory.rent:
      return Icons.home_outlined;
    case SpendCategory.investment:
      return Icons.trending_up_outlined;
    case SpendCategory.cash:
      return Icons.atm_outlined;
    default:
      return Icons.category_outlined;
  }
}

String _coachingLine(SpendMap map) {
  if (map.monthlyIncome <= 0) {
    return 'No salary credit detected in your SMS yet. Add a salary account or '
        'rescan after payday to see realistic savings.';
  }
  final rate = map.savingsRate;
  final top = map.topCategories.isNotEmpty ? map.topCategories.first : null;
  final topLine = top == null
      ? ''
      : ' Your biggest lever is ${SpendCategory.label(top.key).toLowerCase()} '
          '(${money0(top.value)}).';
  if (rate >= 0.3) {
    return 'Strong — you keep ${(rate * 100).round()}% of income. '
        'Automate ${money0(map.realisticMonthlySavings)} on payday toward your goal.$topLine';
  }
  if (rate > 0) {
    return 'You currently save ${(rate * 100).round()}%. Trimming one category could '
        'lift this.$topLine';
  }
  return 'Spending matches or exceeds detected income. Review your largest '
      'categories before committing to a goal.$topLine';
}
