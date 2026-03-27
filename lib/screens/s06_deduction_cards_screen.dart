import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/tax_result_provider.dart';
import '../widgets/gap_card_widget.dart';
import '../widgets/animated_number.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/arth_bottom_nav.dart';

class DeductionCardsScreen extends ConsumerWidget {
  const DeductionCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);
    final doneMap = ref.watch(gapStateProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: ArthAppBar(
        title: 'Your Tax Gaps',
        actions: [
          TextButton(
            onPressed: () => context.push('/action-plan'),
            child: Text('Action Plan',
                style: AppTextStyles.caption(color: AppColors.gold)),
          ),
        ],
      ),
      body: resultAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (result) {
          final gaps = result.gaps;
          final doneCount = ref.read(gapStateProvider.notifier).doneCount(gaps);
          final remaining =
              ref.read(gapStateProvider.notifier).remainingAmount(gaps);

          if (gaps.isEmpty) {
            return const _EmptyGapsView();
          }

          return Column(
            children: [
              // Header summary
              _GapSummaryHeader(
                totalGap: result.totalGapAmount,
                remaining: remaining,
                doneCount: doneCount,
                totalCount: gaps.length,
              ),

              // Cards list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: gaps.length,
                  itemBuilder: (context, i) {
                    final gap = gaps[i];
                    final isDone = doneMap[gap.id] ?? false;
                    return GapCardWidget(
                      gap: gap,
                      isDone: isDone,
                      onTap: () =>
                          context.push('/deduction-detail', extra: gap),
                      onMarkDone: () =>
                          ref.read(gapStateProvider.notifier).toggle(gap.id),
                    )
                        .animate(delay: Duration(milliseconds: i * 80))
                        .slideX(
                            begin: 0.05,
                            duration: 350.ms,
                            curve: Curves.easeOut)
                        .fadeIn(duration: 350.ms);
                  },
                ),
              ),

              // Bottom nav
              ArthBottomNav(
                selectedIndex: 0,
                onTap: (i) {
                  switch (i) {
                    case 0:
                      context.go('/gap-reveal');
                      break;
                    case 1:
                      context.go('/action-plan');
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

class _GapSummaryHeader extends StatelessWidget {
  final int totalGap;
  final int remaining;
  final int doneCount;
  final int totalCount;

  const _GapSummaryHeader({
    required this.totalGap,
    required this.remaining,
    required this.doneCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCount > 0 ? doneCount / totalCount : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Gap', style: AppTextStyles.micro()),
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
                    Text('Still recoverable', style: AppTextStyles.micro()),
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
                    minHeight: 6,
                    backgroundColor: AppColors.bgSurface,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.success),
                  ),
                ),
              ),
              Text(
                '$doneCount of $totalCount done',
                style: AppTextStyles.micro(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyGapsView extends StatelessWidget {
  const _EmptyGapsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_outlined,
                size: 64, color: AppColors.gold),
            const SizedBox(height: 20),
            Text('No gaps found!',
                style: AppTextStyles.h2(color: AppColors.gold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Your deductions appear fully optimised. Consider reviewing in old regime.',
              style: AppTextStyles.body(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
