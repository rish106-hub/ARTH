import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/gap_card.dart';
import '../models/tax_result.dart';
import '../providers/tax_result_provider.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/tax_rule_badge.dart';

class GapRevealScreen extends ConsumerStatefulWidget {
  final bool paycheckMode;

  const GapRevealScreen({super.key, this.paycheckMode = false});

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
      bottomNavigationBar: widget.paycheckMode
          ? null
          : ArthBottomNav(
              selectedIndex: 2,
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
          return _TaxCockpit(
            result: result,
            doneMap: doneMap,
            paycheckMode: widget.paycheckMode,
          );
        },
      ),
    );
  }
}

class _TaxCockpit extends StatelessWidget {
  final TaxResult result;
  final Map<String, bool> doneMap;
  final bool paycheckMode;

  const _TaxCockpit({
    required this.result,
    required this.doneMap,
    required this.paycheckMode,
  });

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
          eyebrow: paycheckMode ? 'Small tool' : 'Discover',
          title: paycheckMode ? 'Your tax plan' : 'Tax Cockpit',
          leading: paycheckMode
              ? IconButton(
                  key: const Key('tax_result_back'),
                  tooltip: 'Back to tax planning',
                  onPressed: () => context.go('/tax-plan'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: PaycheckColors.textSecondary,
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Share',
              onPressed: () => context.push('/share'),
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              color: PaycheckColors.textSecondary,
            ),
            if (paycheckMode)
              TextButton(
                key: const Key('tax_result_done'),
                onPressed: () => context.go('/paycheck/you'),
                child: const Text('Done'),
              ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                        color: PaycheckColors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: ArthMetricCard(
                        label: 'Sync',
                        value: 'Cloud',
                        helper: 'Profile saved',
                        icon: Icons.cloud_done_rounded,
                        color: PaycheckColors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const ArthSection(
                  title: 'Everything tax',
                  child: Column(
                    children: [
                      _FutureModuleTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Tax reminders',
                        body:
                            'Smart nudges before filing and investment deadlines.',
                      ),
                      SizedBox(height: 12),
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
      padding: const EdgeInsets.all(20),
      tint: PaycheckColors.gold,
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
            style: PaycheckType.body(color: PaycheckColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedRupeeNumber(
              value: result.deductionOpportunity,
              duration: const Duration(milliseconds: 1400),
              style: PaycheckType.display(color: PaycheckColors.gold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasGap
                ? '${result.gapCount} opportunities ranked by impact. Estimated tax benefit: ${formatRupeesCompact(result.estimatedTaxBenefit)}.'
                : 'Keep documents ready and re-check when income changes.',
            style: PaycheckType.body(color: PaycheckColors.textSecondary),
          ),
          if (result.assumptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${result.assumptions.length} calculation assumption${result.assumptions.length == 1 ? '' : 's'} active. Add exact inputs to tighten the result.',
              style: PaycheckType.micro(color: PaycheckColors.amber),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Action progress',
                style: PaycheckType.micro(color: PaycheckColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: PaycheckType.micro(color: PaycheckColors.success)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: PaycheckColors.bgSurface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                PaycheckColors.success,
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
          Text('NEXT BEST ACTION', style: PaycheckType.sectionLabel()),
          const SizedBox(height: 12),
          Text(gap.title, style: PaycheckType.h2()),
          const SizedBox(height: 8),
          Text(
            gap.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: PaycheckType.body(color: PaycheckColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Opportunity ${formatRupees(gap.gapAmount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaycheckType.heading(color: PaycheckColors.gold),
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
          const Icon(Icons.compare_arrows_rounded, color: PaycheckColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best regime today', style: PaycheckType.micro()),
                const SizedBox(height: 4),
                Text(
                  '$regime regime saves ${formatRupeesCompact(result.regimeSavings.round())}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PaycheckType.heading(),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Compare regimes',
            onPressed: () => context.push('/regime-comparison'),
            icon: const Icon(Icons.arrow_forward_rounded),
            color: PaycheckColors.gold,
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
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: PaycheckColors.textSecondary, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.heading()),
                const SizedBox(height: 4),
                Text(
                  body,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.lock_clock_outlined,
            color: PaycheckColors.info,
            size: 18,
          ),
        ],
      ),
    );
  }
}
