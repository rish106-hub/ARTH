import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../providers/tax_result_provider.dart';
import '../widgets/animated_number.dart';
import '../widgets/gap_card_widget.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/locked_diagnostic_state.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';

class ActionPlanScreen extends ConsumerWidget {
  const ActionPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);
    final doneMap = ref.watch(gapStateProvider);

    return Scaffold(
      backgroundColor: PaycheckColors.bgPrimary,
      appBar: ArthAppBar(
        title: 'Tax plan',
        actions: [
          IconButton(
            icon: const Icon(
              Icons.ios_share_rounded,
              size: 20,
              color: PaycheckColors.textSecondary,
            ),
            onPressed: () => context.push('/share'),
          ),
        ],
      ),
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
      ),
      body: resultAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Preparing your action plan',
          insights: [
            'Grouping tasks by effort.',
            'Keeping the plan deadline-aware.',
            'Turning gaps into simple steps.',
          ],
        ),
        error: (error, __) => isIncompleteTaxProfileError(error)
            ? const _ActionPlanEmptyState()
            : RetryErrorState(
                message: 'Could not load your action plan.',
                onRetry: () => ref.invalidate(taxResultProvider),
              ),
        data: (result) {
          final gaps = result.gaps;
          final notifier = ref.read(gapStateProvider.notifier);
          final doneCount = notifier.doneCount(gaps);
          final remaining = notifier.remainingAmount(gaps);
          final progress = gaps.isNotEmpty ? doneCount / gaps.length : 0.0;

          final pending = gaps.where((g) => !(doneMap[g.id] ?? false)).toList();
          final done = gaps.where((g) => doneMap[g.id] ?? false).toList();

          return Column(
            children: [
              // Sticky header
              _ActionPlanHeader(
                totalGap: result.totalGapAmount,
                remaining: remaining,
                doneCount: doneCount,
                totalCount: gaps.length,
                progress: progress,
              ),

              // List
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _ActionShortcut(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Compare regimes',
                        body: 'See the tax estimate behind this plan.',
                        onTap: () => context.push('/regime-comparison'),
                      ),
                      _ActionShortcut(
                        icon: Icons.tune_rounded,
                        title: 'Try a scenario',
                        body: 'Change an input without replacing your plan.',
                        onTap: () => context.push('/tax-simulator'),
                      ),
                      _ActionShortcut(
                        icon: Icons.folder_outlined,
                        title: 'Prepare proof',
                        body: 'Move supporting documents into the Vault.',
                        onTap: () => context.push('/documents'),
                      ),
                      if (pending.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'To Do',
                          count: pending.length,
                          color: PaycheckColors.amber,
                        ),
                        ...pending.asMap().entries.map((e) {
                          final gap = e.value;
                          return ActionListItem(
                            gap: gap,
                            isDone: false,
                            onTap: () => context.push(
                              '/deduction-detail',
                              extra: gap,
                            ),
                            onToggle: () => ref
                                .read(gapStateProvider.notifier)
                                .toggle(gap.id),
                          )
                              .animate(
                                delay: Duration(milliseconds: e.key * 60),
                              )
                              .fadeIn(duration: 300.ms)
                              .slideX(begin: 0.05, duration: 300.ms);
                        }),
                      ],
                      if (done.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _SectionHeader(
                          title: 'Done',
                          count: done.length,
                          color: PaycheckColors.success,
                        ),
                        ...done.map(
                          (gap) => ActionListItem(
                            gap: gap,
                            isDone: true,
                            onTap: () =>
                                context.push('/deduction-detail', extra: gap),
                            onToggle: () => ref
                                .read(gapStateProvider.notifier)
                                .toggle(gap.id),
                          ),
                        ),
                      ],
                      if (pending.isEmpty && done.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: Icon(
                              Icons.verified_outlined,
                              size: 64,
                              color: PaycheckColors.gold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionPlanEmptyState extends StatelessWidget {
  const _ActionPlanEmptyState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArthStatePanel(
            icon: Icons.checklist_rounded,
            title: 'Actions start with your diagnostic',
            message:
                'You can still prepare documents now. Complete the diagnostic to unlock personal deduction tasks.',
            actionLabel: 'Start diagnostic',
            onAction: () => context.go('/questions'),
          ),
          _ActionShortcut(
            icon: Icons.folder_special_outlined,
            title: 'Prepare document checklist',
            body:
                'Mark proof readiness now. ARTH stores checklist status only, not files.',
            onTap: () => context.push('/documents'),
          ),
        ],
      ),
    );
  }
}

class _ActionShortcut extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _ActionShortcut({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PaycheckColors.divider)),
        ),
        child: ListTile(
          minTileHeight: 72,
          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
          leading: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: PaycheckColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: PaycheckColors.primary, size: 20),
          ),
          title: Text(title, style: PaycheckType.bodyMedium()),
          subtitle: Text(
            body,
            style: PaycheckType.caption(color: PaycheckColors.textSecondary),
          ),
          trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ActionPlanHeader extends StatelessWidget {
  final int totalGap;
  final int remaining;
  final int doneCount;
  final int totalCount;
  final double progress;

  const _ActionPlanHeader({
    required this.totalGap,
    required this.remaining,
    required this.doneCount,
    required this.totalCount,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: PaycheckColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR OPEN PLAN',
            style: PaycheckType.sectionLabel(
              color: Colors.white60,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Possible deductions',
                      style: PaycheckType.micro(color: Colors.white60),
                    ),
                    Text(
                      formatRupeesCompact(totalGap),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PaycheckType.h2(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Still to review',
                      style: PaycheckType.micro(color: Colors.white60),
                    ),
                    Text(
                      formatRupeesCompact(remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: PaycheckType.h2(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.pill,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      PaycheckColors.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$doneCount of $totalCount done',
                style: PaycheckType.caption(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.pill,
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: PaycheckType.h3()),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.pill,
            ),
            child: Text('$count', style: PaycheckType.micro(color: color)),
          ),
        ],
      ),
    );
  }
}
