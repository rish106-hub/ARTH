import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../features/spend_completeness/providers/spend_completeness_provider.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../engine/work_cost_lens_engine.dart';
import '../models/work_cost_models.dart';
import '../providers/work_cost_provider.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

class WorkCostLensScreen extends ConsumerStatefulWidget {
  const WorkCostLensScreen({super.key});

  @override
  ConsumerState<WorkCostLensScreen> createState() => _WorkCostLensScreenState();
}

class _WorkCostLensScreenState extends ConsumerState<WorkCostLensScreen> {
  /// The candidate count is only meaningful once the spend map has loaded, and
  /// this screen rebuilds on every tag change — so report the first real count
  /// and nothing after it, or one visit would look like many.
  bool _reportedCandidateCount = false;

  @override
  Widget build(BuildContext context) {
    final spend = ref.watch(spendMapProvider);
    final settings = ref.watch(workCostProvider);
    final completeness = ref.watch(spendCompletenessProvider);
    final incompleteCoverage = completeness.missingSources.isNotEmpty;
    final map = spend.map;
    final allCandidates = map == null
        ? const <WorkCostCandidate>[]
        : WorkCostLensEngine.candidates(map);
    final candidates = allCandidates
        .where((candidate) =>
            !settings.dismissedCandidateIds.contains(candidate.id))
        .toList(growable: false);

    if (map != null && !_reportedCandidateCount) {
      _reportedCandidateCount = true;
      final count = candidates.length;
      // After the frame: build must stay free of side effects.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(analyticsProvider).workCostCandidatesShown(count);
      });
    }

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        foregroundColor: PaycheckColors.ink,
        elevation: 0,
        title: Text('Workday costs', style: PaycheckType.heading()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Find the cost of having a job.', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'ARTH finds repeat purchases. You decide if they are work costs.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 24),
          if (map == null || map.isEmpty)
            _EmptyLens(onScan: () => context.push('/spend-map'))
          else if (candidates.isEmpty)
            const _NoCandidates()
          else ...[
            Text('Repeat costs to review', style: PaycheckType.heading()),
            const SizedBox(height: 12),
            for (final candidate in candidates) ...[
              _CandidateCard(
                candidate: candidate,
                tag: settings.tags[candidate.id],
                experiment: settings.experiments[candidate.id],
                incompleteCoverage: incompleteCoverage,
                onChoose: () => _chooseKind(context, ref, candidate.id),
                onRemove: () =>
                    ref.read(workCostProvider.notifier).removeTag(candidate.id),
                onDismiss: () =>
                    ref.read(workCostProvider.notifier).dismiss(candidate.id),
                onStartExperiment: () =>
                    ref.read(workCostProvider.notifier).startExperiment(
                          candidate.id,
                          candidate.oneLessPerWeekSavings,
                        ),
                onDecideExperiment: (kept) =>
                    ref.read(workCostProvider.notifier).decideExperiment(
                          candidate.id,
                          kept: kept,
                        ),
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 16),
          Text(
            'Only itemised SMS purchases count. Cash and card bills stay out.',
            style: PaycheckType.utility(color: PaycheckColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseKind(
    BuildContext context,
    WidgetRef ref,
    String candidateId,
  ) async {
    final selected = await showModalBottomSheet<WorkCostKind>(
      context: context,
      showDragHandle: true,
      backgroundColor: PaycheckColors.paper,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('What is this cost?', style: PaycheckType.heading()),
            ),
            for (final kind in WorkCostKind.values)
              ListTile(
                title: Text(kind.label),
                onTap: () => Navigator.pop(sheetContext, kind),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(workCostProvider.notifier).setTag(candidateId, selected);
    }
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.tag,
    required this.experiment,
    required this.incompleteCoverage,
    required this.onChoose,
    required this.onRemove,
    required this.onDismiss,
    required this.onStartExperiment,
    required this.onDecideExperiment,
  });

  final WorkCostCandidate candidate;
  final WorkCostTag? tag;
  final WorkCostExperiment? experiment;
  final bool incompleteCoverage;
  final VoidCallback onChoose;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;
  final VoidCallback onStartExperiment;
  final ValueChanged<bool> onDecideExperiment;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PaycheckColors.paper,
          border: Border.all(color: PaycheckColors.line),
          borderRadius: AppRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(candidate.merchant,
                      style: PaycheckType.bodyStrong()),
                ),
                if (tag != null)
                  Text(tag!.kind.label,
                      style:
                          PaycheckType.utility(color: PaycheckColors.contract)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_money(candidate.monthlyAmount)} tracked each month · ${candidate.transactionCount} purchases',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 4),
            Text(
              '${_money(candidate.monthlyAmount * 12)} in 12 months if unchanged',
              style: PaycheckType.utility(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 12),
            if (tag == null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onChoose,
                    child: const Text('Mark as a work cost'),
                  ),
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Not work-related'),
                  ),
                ],
              )
            else ...[
              Text(
                'Try one less each workweek: save about ${_money(candidate.oneLessPerWeekSavings)} per month.',
                style: PaycheckType.bodyStrong(color: PaycheckColors.matched),
              ),
              if (incompleteCoverage) ...[
                const SizedBox(height: 4),
                Text(
                  'Your SMS coverage looks incomplete, so this saving is an estimate, not a guarantee.',
                  style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                ),
              ],
              const SizedBox(height: 12),
              _ExperimentControls(
                experiment: experiment,
                onStart: onStartExperiment,
                onDecide: onDecideExperiment,
              ),
              TextButton(
                  onPressed: onRemove, child: const Text('Remove work tag')),
            ],
          ],
        ),
      );
}

/// Turns the suggestion into something the user can commit to and then judge.
///
/// Reading a saving and acting on one are different events, and only the second
/// says the lens works, so the commitment is state rather than a nudge.
class _ExperimentControls extends StatelessWidget {
  const _ExperimentControls({
    required this.experiment,
    required this.onStart,
    required this.onDecide,
  });

  final WorkCostExperiment? experiment;
  final VoidCallback onStart;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final current = experiment;
    if (current == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          key: const Key('work_cost_experiment_start'),
          onPressed: onStart,
          child: const Text('I will try this'),
        ),
      );
    }

    if (!current.status.isDecided) {
      final days = current.daysRunning(DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            days < 1
                ? 'Trying this since today.'
                : 'Trying this for ${days == 1 ? '1 day' : '$days days'}.',
            style: PaycheckType.utility(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('work_cost_experiment_kept'),
                onPressed: () => onDecide(true),
                child: const Text('It stuck'),
              ),
              TextButton(
                key: const Key('work_cost_experiment_stopped'),
                onPressed: () => onDecide(false),
                child: const Text('I stopped'),
              ),
            ],
          ),
        ],
      );
    }

    final kept = current.status == WorkCostExperimentStatus.kept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kept
              ? 'Kept: about ${_money(current.monthlyTarget)} a month less on this.'
              : 'Stopped. Nothing wrong with that — the cost stays visible.',
          style: PaycheckType.utility(
            color: kept ? PaycheckColors.matched : PaycheckColors.inkSoft,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('work_cost_experiment_restart'),
            onPressed: onStart,
            child: const Text('Try it again'),
          ),
        ),
      ],
    );
  }
}

class _EmptyLens extends StatelessWidget {
  const _EmptyLens({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: PaycheckColors.paper,
          borderRadius: AppRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scan SMS to find repeat costs',
                style: PaycheckType.heading()),
            const SizedBox(height: 8),
            Text(
                'ARTH needs itemised transaction history before it can show patterns.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: onScan, child: const Text('Open expenses from SMS')),
          ],
        ),
      );
}

class _NoCandidates extends StatelessWidget {
  const _NoCandidates();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: PaycheckColors.paper,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          'No repeat merchants yet. ARTH needs three matching purchases first.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft),
        ),
      );
}
