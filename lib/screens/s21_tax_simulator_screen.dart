import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../engine/tax_engine.dart';
import '../providers/tax_result_provider.dart';
import '../providers/tax_year_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';
import '../widgets/tax_rule_badge.dart';

class TaxSimulatorScreen extends ConsumerStatefulWidget {
  final bool paycheckMode;

  const TaxSimulatorScreen({super.key, this.paycheckMode = false});

  @override
  ConsumerState<TaxSimulatorScreen> createState() => _TaxSimulatorScreenState();
}

class _TaxSimulatorScreenState extends ConsumerState<TaxSimulatorScreen> {
  late double _invest80c;
  late double _nps;
  late double _health80d;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final completeAsync = ref.watch(completedTaxProfileProvider);
    return ArthScaffold(
      bottomNavigationBar: widget.paycheckMode
          ? null
          : ArthBottomNav(
              selectedIndex: 2,
              onTap: (i) => goToArthTab(context, i),
            ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'What-if',
            title: 'Tax Simulator',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(
                    widget.paycheckMode ? '/tax-plan/results' : '/discover',
                  );
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
              color: PaycheckColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Opening simulator',
                insights: ['Loading deterministic tax rules.'],
              ),
              error: (_, __) => RetryErrorState(
                message: 'Could not check diagnostic status.',
                onRetry: () => ref.invalidate(completedTaxProfileProvider),
              ),
              data: (complete) {
                if (!complete) {
                  return ArthStatePanel(
                    icon: Icons.science_outlined,
                    title: 'Diagnostic needed',
                    message:
                        'Run the diagnostic once so simulator changes have a real baseline.',
                    actionLabel: 'Start diagnostic',
                    onAction: () => context.go(
                      widget.paycheckMode
                          ? '/tax-plan/questions'
                          : '/questions',
                    ),
                  );
                }
                final profile = ref.watch(userProfileProvider);
                if (!_seeded) {
                  _invest80c = profile.invested80C.toDouble();
                  _nps = profile.npsExtraContribution.toDouble();
                  _health80d =
                      (profile.healthInsuranceSelfPremium ?? 0).toDouble();
                  _seeded = true;
                }
                final resultAsync = ref.watch(taxResultProvider);
                final ruleSetAsync = ref.watch(activeTaxRuleSetProvider);
                return resultAsync.when(
                  loading: () => const ArthLoadingPanel(
                    title: 'Preparing baseline',
                    insights: ['Computing current regime comparison.'],
                  ),
                  error: (_, __) => RetryErrorState(
                    message: 'Could not load simulator baseline.',
                    onRetry: () => ref.invalidate(taxResultProvider),
                  ),
                  data: (current) => ruleSetAsync.when(
                    loading: () => const ArthLoadingPanel(
                      title: 'Loading tax year',
                      insights: ['Checking active rule set.'],
                    ),
                    error: (_, __) => RetryErrorState(
                      message: 'Could not load active tax rules.',
                      onRetry: () => ref.invalidate(activeTaxRuleSetProvider),
                    ),
                    data: (ruleSet) {
                      final simulatedProfile = profile.copyWith(
                        invested80C: _invest80c.round(),
                        npsExtraContribution: _nps.round(),
                        hasNPS: _nps > 0 || profile.hasNPS,
                        hasHealthInsuranceSelf:
                            _health80d > 0 || profile.hasHealthInsuranceSelf,
                        healthInsuranceSelfPremium: _health80d.round(),
                      );
                      final simulated = TaxEngine.calculate(
                        simulatedProfile,
                        current.gaps,
                        ruleSet: ruleSet,
                      );
                      final benefit =
                          (current.currentTax - simulated.currentTax)
                              .clamp(0, double.infinity)
                              .round();
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PremiumGlassPanel(
                              elevated: true,
                              borderRadius: BorderRadius.circular(28),
                              tint: PaycheckColors.gold,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const TrustBadge(
                                    icon: Icons.functions_rounded,
                                    label: 'Deterministic estimate',
                                  ),
                                  const SizedBox(height: 16),
                                  Text('Try a tax-saving move',
                                      style: PaycheckType.h1()),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Change 80C, NPS, and 80D values without touching your saved diagnostic.',
                                    style: PaycheckType.body(
                                      color: PaycheckColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TaxRuleBadge(result: current),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ArthMetricCard(
                                    label: 'Possible benefit',
                                    value: formatRupeesCompact(benefit),
                                    helper: 'vs current estimate',
                                    icon: Icons.savings_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ArthMetricCard(
                                    label: 'Best regime',
                                    value: simulated.betterRegimeLabel,
                                    helper:
                                        '${simulated.confidenceScore}% confidence',
                                    icon: Icons.compare_arrows_rounded,
                                    color: PaycheckColors.teal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _SimulatorSlider(
                              title: '80C investment',
                              value: _invest80c,
                              max: 150000,
                              onChanged: (value) =>
                                  setState(() => _invest80c = value),
                            ),
                            const SizedBox(height: 12),
                            _SimulatorSlider(
                              title: 'Extra NPS 80CCD(1B)',
                              value: _nps,
                              max: 50000,
                              onChanged: (value) =>
                                  setState(() => _nps = value),
                            ),
                            const SizedBox(height: 12),
                            _SimulatorSlider(
                              title: 'Self/family 80D premium',
                              value: _health80d,
                              max: profile.ageAbove60 ? 50000 : 25000,
                              onChanged: (value) =>
                                  setState(() => _health80d = value),
                            ),
                            const SizedBox(height: 16),
                            PremiumGlassPanel(
                              tint: PaycheckColors.teal,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Assumption guardrail',
                                      style: PaycheckType.h3()),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Nothing changes unless you apply it.',
                                    style: PaycheckType.caption(
                                      color: PaycheckColors.textSecondary,
                                    ),
                                  ),
                                  const ArthDisclosure(
                                    label: 'What this screen does not do',
                                    detail:
                                        'It does not file an ITR and does not touch your profile. Tax shown follows the active rule set and your current assumptions.',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: AppButtons.primaryGold,
                              onPressed: () async {
                                final notifier =
                                    ref.read(userProfileProvider.notifier);
                                final previous = ref.read(userProfileProvider);
                                notifier.updateField(
                                  (_) => simulatedProfile,
                                );
                                try {
                                  await notifier.save();
                                  ref.invalidate(taxResultProvider);
                                  await computeAndSyncCurrentTaxResult(ref);
                                  if (context.mounted) {
                                    HapticFeedback.selectionClick();
                                    context.go('/gap-reveal');
                                  }
                                } catch (_) {
                                  notifier.update(previous);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Could not apply this scenario. Please try again.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Apply to diagnostic'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulatorSlider extends StatelessWidget {
  final String title;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  const _SimulatorSlider({
    required this.title,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: PaycheckType.bodyMedium())),
              Text(
                formatRupeesCompact(value.round()),
                style: PaycheckType.caption(color: PaycheckColors.gold),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            divisions: max <= 50000 ? 10 : 15,
            label: formatRupeesCompact(value.round()),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
