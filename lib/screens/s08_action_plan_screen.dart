import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/tax_result_provider.dart';
import '../widgets/animated_number.dart';
import '../widgets/gap_card_widget.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';

class ActionPlanScreen extends ConsumerWidget {
  const ActionPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);
    final doneMap = ref.watch(gapStateProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: ArthAppBar(
        title: 'Your Action Plan',
        actions: [
          IconButton(
            icon: const Icon(
              Icons.ios_share_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            onPressed: () => context.push('/share'),
          ),
        ],
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
        error: (_, __) => RetryErrorState(
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
                      if (pending.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'To Do',
                          count: pending.length,
                          color: AppColors.amber,
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
                          color: AppColors.success,
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
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom nav
              ArthBottomNav(
                selectedIndex: 1,
                onTap: (i) {
                  switch (i) {
                    case 0:
                      context.go('/gap-reveal');
                      break;
                    case 1:
                      break;
                    case 2:
                      context.go('/progress');
                      break;
                    case 3:
                      context.go('/settings');
                      break;
                  }
                },
              ),
            ],
          );
        },
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR ARTH ACTION PLAN',
            style: AppTextStyles.sectionLabel(
              color: AppColors.textSecondary,
            ).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total recoverable', style: AppTextStyles.micro()),
                    Text(
                      formatRupeesCompact(totalGap),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h2(color: AppColors.gold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Still pending', style: AppTextStyles.micro()),
                    Text(
                      formatRupeesCompact(remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTextStyles.h2(color: AppColors.amber),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: AppRadius.pill,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppColors.bgSurface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.success,
                    ),
                  ),
                ),
              ),
              Text(
                '$doneCount of $totalCount done',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
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
          Text(title, style: AppTextStyles.h3()),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.pill,
            ),
            child: Text('$count', style: AppTextStyles.micro(color: color)),
          ),
        ],
      ),
    );
  }
}
