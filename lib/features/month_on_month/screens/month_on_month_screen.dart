import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/spend_map.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/premium_ui.dart';
import '../engine/month_on_month_engine.dart';

class MonthOnMonthScreen extends ConsumerWidget {
  const MonthOnMonthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendMapProvider);
    final map = state.map;

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        elevation: 0,
        foregroundColor: PaycheckColors.ink,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('Month on month', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        child: map == null || map.isEmpty
            ? ArthStatePanel(
                icon: Icons.calendar_month_outlined,
                title: 'No months to compare yet',
                message: 'Build your spend map first.',
                actionLabel: 'Open spend map',
                onAction: () => context.go('/spend-map'),
              )
            : _Months(map: map),
      ),
    );
  }
}

class _Months extends StatelessWidget {
  const _Months({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final months = MonthOnMonthEngine.compare(map);
    final movers = MonthOnMonthEngine.movers(map);

    if (months.length < 2) {
      return const ArthStatePanel(
        icon: Icons.calendar_month_outlined,
        title: 'Only one month so far',
        message: 'Scan a longer window to compare months.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EVERY MONTH', style: PaycheckType.utility()),
          const SizedBox(height: 8),
          for (final month in months) ...[
            _MonthCard(month: month),
            const SizedBox(height: 12),
          ],
          if (movers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('WHAT MOVED', style: PaycheckType.utility()),
            const SizedBox(height: 4),
            Text(
              'Against the month before.',
              style: PaycheckType.caption(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 8),
            for (final move in movers) ...[
              _MoverRow(move: move),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month});

  final MonthComparison month;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy').format(month.month);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: PaycheckType.bodyStrong())),
              _NetPill(net: month.net),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Spent',
                  amount: month.spent,
                  change: month.spentChange,
                  // For spend, up is the bad direction.
                  upIsGood: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  label: 'Income',
                  amount: month.income,
                  change: month.incomeChange,
                  upIsGood: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.change,
    required this.upIsGood,
  });

  final String label;
  final int amount;
  final int? change;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final delta = change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PaycheckType.utility()),
        const SizedBox(height: 4),
        Text(money0(amount), style: PaycheckType.title()),
        const SizedBox(height: 4),
        if (delta == null)
          // The first month in the window has nothing behind it. Saying so beats
          // showing a change of zero, which would read as "no change".
          Text(
            'First month',
            style: PaycheckType.utility(color: PaycheckColors.inkMuted),
          )
        else
          _Delta(change: delta, upIsGood: upIsGood),
      ],
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.change, required this.upIsGood});

  final int change;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    if (change == 0) {
      return Text(
        'Unchanged',
        style: PaycheckType.utility(color: PaycheckColors.inkMuted),
      );
    }
    final isUp = change > 0;
    final good = isUp == upIsGood;
    final color = good ? PaycheckColors.matched : PaycheckColors.claim;
    return Row(
      children: [
        Icon(
          isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            money0(change.abs()),
            style: PaycheckType.utility(color: color),
          ),
        ),
      ],
    );
  }
}

class _NetPill extends StatelessWidget {
  const _NetPill({required this.net});

  final int net;

  @override
  Widget build(BuildContext context) {
    final saved = net >= 0;
    final color = saved ? PaycheckColors.matched : PaycheckColors.claim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        '${saved ? 'Saved' : 'Short'} ${money0(net.abs())}',
        style: PaycheckType.utility(color: color),
      ),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.move});

  final CategoryMonthMove move;

  @override
  Widget build(BuildContext context) {
    final color = move.isUp ? PaycheckColors.claim : PaycheckColors.matched;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.control,
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              SpendCategory.label(move.category),
              style: PaycheckType.bodyMedium(),
            ),
          ),
          Text(
            '${move.isUp ? '+' : '−'}${money0(move.magnitude)}',
            style: PaycheckType.bodyStrong(color: color),
          ),
        ],
      ),
    );
  }
}
