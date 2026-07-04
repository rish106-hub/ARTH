import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/gap_card.dart';
import '../models/tax_result.dart';
import '../providers/tax_result_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/tax_rule_badge.dart';

class GapRevealScreen extends ConsumerStatefulWidget {
  const GapRevealScreen({super.key});

  @override
  ConsumerState<GapRevealScreen> createState() => _GapRevealScreenState();
}

class _GapRevealScreenState extends ConsumerState<GapRevealScreen> {
  bool _hapticPlayed = false;

  void _playRevealHaptic(int amount) {
    if (_hapticPlayed) return;
    _hapticPlayed = true;
    if (amount > 0) HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(taxResultProvider);
    final doneMap = ref.watch(gapStateProvider);

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 0,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: resultAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Building your tax cockpit',
          insights: [
            'Calculating missed deductions.',
            'Comparing old and new regimes.',
            'Finding your next best action.',
          ],
        ),
        error: (_, __) => ArthStatePanel(
          icon: Icons.refresh_rounded,
          title: 'Could not build cockpit',
          message: 'Your profile is safe. Retry when the connection is stable.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(taxResultProvider),
        ),
        data: (result) {
          _playRevealHaptic(result.totalGapAmount);
          return _TaxCockpit(result: result, doneMap: doneMap);
        },
      ),
    );
  }
}

class _TaxCockpit extends StatelessWidget {
  final TaxResult result;
  final Map<String, bool> doneMap;

  const _TaxCockpit({required this.result, required this.doneMap});

  @override
  Widget build(BuildContext context) {
    final pending = result.gaps.where((gap) => !(doneMap[gap.id] ?? false));
    final nextGap = pending.isEmpty ? null : pending.first;
    final doneCount =
        result.gaps.where((gap) => doneMap[gap.id] ?? false).length;
    final progress = result.gaps.isEmpty
        ? 1.0
        : (doneCount / result.gaps.length).clamp(0.0, 1.0);

    return Column(
      children: [
        ArthPremiumAppBar(
          eyebrow: 'Discover',
          title: 'Tax Cockpit',
          actions: [
            IconButton(
              tooltip: 'Share',
              onPressed: () => context.push('/share'),
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              color: AppColors.textSecondary,
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroCockpitCard(result: result, progress: progress),
                const SizedBox(height: 16),
                _NextActionCard(nextGap: nextGap),
                const SizedBox(height: 16),
                _RegimeInsightCard(result: result),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ArthMetricCard(
                        label: 'Open gaps',
                        value: '${result.gapCount - doneCount}',
                        helper: '$doneCount completed',
                        icon: Icons.radar_rounded,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ArthMetricCard(
                        label: 'Sync',
                        value: 'Cloud',
                        helper: 'Profile saved',
                        icon: Icons.cloud_done_rounded,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ArthSection(
                  title: 'Everything tax',
                  child: Column(
                    children: const [
                      _FutureModuleTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Tax reminders',
                        body:
                            'Smart nudges before filing and investment deadlines.',
                      ),
                      SizedBox(height: 10),
                      _FutureModuleTile(
                        icon: Icons.folder_special_outlined,
                        title: 'Proof vault',
                        body: 'A future opt-in place for deduction documents.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCockpitCard extends StatelessWidget {
  final TaxResult result;
  final double progress;

  const _HeroCockpitCard({required this.result, required this.progress});

  @override
  Widget build(BuildContext context) {
    final hasGap = result.totalGapAmount > 0;
    return PremiumGlassPanel(
      elevated: true,
      borderRadius: BorderRadius.circular(30),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TrustBadge(
                icon: hasGap
                    ? Icons.auto_awesome_rounded
                    : Icons.verified_rounded,
                label: hasGap
                    ? 'Deduction opportunity found'
                    : 'No major gap found',
              ),
              TaxRuleBadge(result: result),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            hasGap
                ? 'Potential deduction opportunity'
                : 'Your profile looks tight',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedRupeeNumber(
              value: result.deductionOpportunity,
              duration: const Duration(milliseconds: 1400),
              style: AppTextStyles.display(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasGap
                ? '${result.gapCount} opportunities ranked by impact. Estimated tax benefit: ${formatRupeesCompact(result.estimatedTaxBenefit)}.'
                : 'Keep documents ready and re-check when income changes.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          if (result.assumptions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${result.assumptions.length} calculation assumption${result.assumptions.length == 1 ? '' : 's'} active. Add exact inputs to tighten the result.',
              style: AppTextStyles.micro(color: AppColors.amber),
            ),
          ],
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.bgSurface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextActionCard extends StatelessWidget {
  final GapCard? nextGap;

  const _NextActionCard({required this.nextGap});

  @override
  Widget build(BuildContext context) {
    if (nextGap == null) {
      return ArthStatePanel(
        icon: Icons.task_alt_rounded,
        title: 'Action plan complete',
        message: 'You have marked every current gap as done.',
        actionLabel: 'View progress',
        onAction: () => context.go('/progress'),
      );
    }

    final gap = nextGap!;
    return PremiumGlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT BEST ACTION', style: AppTextStyles.sectionLabel()),
          const SizedBox(height: 10),
          Text(gap.title, style: AppTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            gap.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Opportunity ${formatRupees(gap.gapAmount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3(color: AppColors.gold),
                ),
              ),
              ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: () => context.push('/deduction-detail', extra: gap),
                child: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegimeInsightCard extends StatelessWidget {
  final TaxResult result;

  const _RegimeInsightCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final regime = result.betterRegime == TaxRegime.oldRegime ? 'Old' : 'New';
    return PremiumGlassPanel(
      child: Row(
        children: [
          const Icon(Icons.compare_arrows_rounded, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best regime today', style: AppTextStyles.micro()),
                const SizedBox(height: 3),
                Text(
                  '$regime regime saves ${formatRupeesCompact(result.regimeSavings.round())}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3(),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Compare regimes',
            onPressed: () => context.push('/regime-comparison'),
            icon: const Icon(Icons.arrow_forward_rounded),
            color: AppColors.gold,
          ),
        ],
      ),
    );
  }
}

class _FutureModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _FutureModuleTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: AppTextStyles.h3())),
                    const SizedBox(width: 8),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TrustBadge(
                        icon: Icons.lock_clock_rounded,
                        label: 'Soon',
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
