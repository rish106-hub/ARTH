import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/tax_result_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/locked_diagnostic_state.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';

class ProgressTrackerScreen extends ConsumerWidget {
  const ProgressTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);
    final doneMap = ref.watch(gapStateProvider);
    final documentPercent = ref.watch(documentReadinessPercentProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: const ArthAppBar(title: 'Progress Tracker'),
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/discover');
              break;
            case 1:
              context.go('/action-plan');
              break;
            case 2:
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
      ),
      body: resultAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Loading progress',
          insights: [
            'Checking completed actions.',
            'Updating deadline context.',
            'Keeping your tax sprint current.',
          ],
        ),
        error: (error, __) => isIncompleteTaxProfileError(error)
            ? _ProgressEmptyState(documentPercent: documentPercent)
            : RetryErrorState(
                message: 'Could not load your progress.',
                onRetry: () => ref.invalidate(taxResultProvider),
              ),
        data: (result) {
          final gaps = result.gaps;
          final notifier = ref.read(gapStateProvider.notifier);
          final doneCount = notifier.doneCount(gaps);
          final remaining = notifier.remainingAmount(gaps);

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // FY timeline banner
                      const _FYTimeline(),
                      const SizedBox(height: 24),

                      // Overall progress
                      _OverallProgress(
                        totalGap: result.totalGapAmount,
                        remaining: remaining,
                        doneCount: doneCount,
                        totalCount: gaps.length,
                        ruleLabel: result.ruleSetLabel,
                      ),
                      const SizedBox(height: 24),

                      // Key deadlines
                      Text('Key Deadlines', style: AppTextStyles.h3()),
                      const SizedBox(height: 12),
                      const _DeadlineTimeline(),
                      const SizedBox(height: 24),

                      _ReadinessProgressCard(documentPercent: documentPercent),
                      const SizedBox(height: 24),

                      // Gap status grid
                      Text('Gap Status', style: AppTextStyles.h3()),
                      const SizedBox(height: 12),
                      ...gaps.map((gap) {
                        final done = doneMap[gap.id] ?? false;
                        return _GapStatusRow(
                          section: gap.section,
                          title: gap.title,
                          amount: gap.gapAmount,
                          deadline: gap.deadline,
                          isDone: done,
                        );
                      }),
                      const SizedBox(height: 8),
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

class _ProgressEmptyState extends StatelessWidget {
  final int documentPercent;

  const _ProgressEmptyState({required this.documentPercent});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArthStatePanel(
            icon: Icons.timeline_rounded,
            title: 'Progress starts after diagnostic',
            message:
                'Your timeline is visible now. Complete the diagnostic to track savings progress and completed actions.',
            actionLabel: 'Start diagnostic',
            onAction: () => context.go('/questions'),
          ),
          const SizedBox(height: 16),
          const _FYTimeline(),
          const SizedBox(height: 16),
          _ReadinessProgressCard(documentPercent: documentPercent),
        ],
      ),
    );
  }
}

class _ReadinessProgressCard extends StatelessWidget {
  final int documentPercent;

  const _ReadinessProgressCard({required this.documentPercent});

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      tint: AppColors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filing readiness', style: AppTextStyles.h3()),
          const SizedBox(height: 8),
          Text(
            'Document checklist is $documentPercent% ready. Keep AIS/26AS review separate and use official records before filing.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: AppButtons.outlineGold,
                  onPressed: () => context.push('/documents'),
                  icon: const Icon(Icons.folder_special_outlined),
                  label: const Text('Documents'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: AppButtons.outlineGold,
                  onPressed: () => context.push('/ais-guide'),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('AIS guide'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FYTimeline extends StatelessWidget {
  const _FYTimeline();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fyEnd = DateTime(2027, 3, 31);
    final fyStart = DateTime(2026, 4, 1);
    final totalDays = fyEnd.difference(fyStart).inDays;
    final elapsedDays = now.difference(fyStart).inDays.clamp(0, totalDays);
    final progress = elapsedDays / totalDays;
    final daysLeft = fyEnd.difference(now).inDays.clamp(0, 365);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'FY2026-27 Planning',
                  style: AppTextStyles.h3(),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: daysLeft <= 30
                        ? AppColors.alert.withValues(alpha: 0.15)
                        : AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    '$daysLeft days left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro(
                      color: daysLeft <= 30 ? AppColors.alert : AppColors.amber,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.bgSurface,
              valueColor: AlwaysStoppedAnimation<Color>(
                daysLeft <= 30 ? AppColors.alert : AppColors.amber,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Apr 2026', style: AppTextStyles.micro())),
              const SizedBox(width: 8),
              Text('Mar 31, 2027', style: AppTextStyles.micro()),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverallProgress extends StatelessWidget {
  final int totalGap;
  final int remaining;
  final int doneCount;
  final int totalCount;
  final String ruleLabel;

  const _OverallProgress({
    required this.totalGap,
    required this.remaining,
    required this.doneCount,
    required this.totalCount,
    required this.ruleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final claimed = totalGap - remaining;
    final progress = totalGap > 0 ? claimed / totalGap : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gold.withValues(alpha: 0.08), AppColors.bgCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Addressed so far',
                      style: AppTextStyles.micro(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      formatRupeesCompact(claimed),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h2(color: AppColors.success),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Still open',
                      style: AppTextStyles.micro(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      formatRupeesCompact(remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTextStyles.h2(color: AppColors.gold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.bgSurface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$doneCount of $totalCount opportunities addressed • $ruleLabel',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DeadlineTimeline extends StatelessWidget {
  const _DeadlineTimeline();

  static const _deadlines = [
    _Deadline(
      date: 'Mar 31, 2027',
      label: '80C, 80CCD(1B), 80D investments',
      isUrgent: true,
    ),
    _Deadline(
      date: 'Mar 15, 2027',
      label: 'Advance Tax Q4 — pay 100%',
      isUrgent: true,
    ),
    _Deadline(
      date: 'Jul 31, 2027',
      label: 'ITR filing deadline (salaried)',
      isUrgent: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _deadlines.map((d) => _DeadlineRow(deadline: d)).toList(),
      ),
    );
  }
}

class _Deadline {
  final String date;
  final String label;
  final bool isUrgent;
  const _Deadline({
    required this.date,
    required this.label,
    required this.isUrgent,
  });
}

class _DeadlineRow extends StatelessWidget {
  final _Deadline deadline;
  const _DeadlineRow({required this.deadline});

  @override
  Widget build(BuildContext context) {
    final color = deadline.isUrgent ? AppColors.alert : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deadline.label, style: AppTextStyles.caption()),
                Text(deadline.date, style: AppTextStyles.micro(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GapStatusRow extends StatelessWidget {
  final String section;
  final String title;
  final int amount;
  final String deadline;
  final bool isDone;

  const _GapStatusRow({
    required this.section,
    required this.title,
    required this.amount,
    required this.deadline,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: isDone
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? AppColors.success : AppColors.bgSurface,
              border: Border.all(
                color: isDone ? AppColors.success : AppColors.border,
              ),
            ),
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.caption()),
                Text(
                  section,
                  style: AppTextStyles.micro(color: AppColors.gold),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupees(amount),
                style: AppTextStyles.caption(
                  color: isDone ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              Text(
                deadline,
                style: AppTextStyles.micro(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
