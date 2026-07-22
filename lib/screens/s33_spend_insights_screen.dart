import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                'ARTH reads bank & UPI SMS on this phone to map where your money goes. Parsing stays on-device.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 20),
              if (state.loading)
                const _Loading()
              else if (state.permissionDenied)
                _PermissionCard(onRetry: () => ref.read(spendMapProvider.notifier).scan())
              else if (state.error != null)
                _ErrorCard(
                  message: state.error!,
                  onRetry: () => ref.read(spendMapProvider.notifier).scan(),
                )
              else if (!state.hasData)
                _EmptyCard(onScan: () => ref.read(spendMapProvider.notifier).scan())
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
  const _EmptyCard({required this.onScan});
  final VoidCallback onScan;
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
            'We scan the last 120 days of bank & UPI SMS, detect salary credits and spends, and estimate what you can realistically save.',
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
          Text(message, style: PaycheckType.body(color: PaycheckColors.inkSoft)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.map});
  final SpendMap map;

  @override
  Widget build(BuildContext context) {
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
        _CategoryBars(map: map),
        const SizedBox(height: 16),
        Text(
          '${map.txns.length} transactions across ${map.monthsSpan} month(s), '
          'ending ${DateFormat('d MMM').format(map.windowEnd)}.',
          style: PaycheckType.utility(),
        ),
      ],
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PaycheckColors.matched.withValues(alpha: 0.4)),
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
            Text('$rate% of detected income',
                style: PaycheckType.utility()),
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
          Text(label.toUpperCase(),
              style: PaycheckType.utility(color: color)),
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
        borderRadius: BorderRadius.circular(16),
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

