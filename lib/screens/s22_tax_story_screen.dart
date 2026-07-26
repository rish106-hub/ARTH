import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../models/tax_document.dart';
import '../models/tax_readiness.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
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

class TaxStoryScreen extends ConsumerWidget {
  const TaxStoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeAsync = ref.watch(completedTaxProfileProvider);
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Story',
            title: 'My Tax Story',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/discover');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
              color: PaycheckColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Opening Tax Story',
                insights: ['Preparing your summary.'],
              ),
              error: (_, __) => RetryErrorState(
                message: 'Could not check diagnostic status.',
                onRetry: () => ref.invalidate(completedTaxProfileProvider),
              ),
              data: (complete) {
                if (!complete) {
                  return ArthStatePanel(
                    icon: Icons.auto_stories_outlined,
                    title: 'Your story starts after diagnostic',
                    message:
                        'Complete the diagnostic once to generate your tax-readiness story.',
                    actionLabel: 'Start diagnostic',
                    onAction: () => context.go('/questions'),
                  );
                }
                final resultAsync = ref.watch(taxResultProvider);
                return resultAsync.when(
                  loading: () => const ArthLoadingPanel(
                    title: 'Building story',
                    insights: ['Summarising readiness and next actions.'],
                  ),
                  error: (_, __) => RetryErrorState(
                    message: 'Could not load your Tax Story.',
                    onRetry: () => ref.invalidate(taxResultProvider),
                  ),
                  data: (result) {
                    final profile = ref.watch(userProfileProvider);
                    final checklist = ref.watch(documentChecklistProvider);
                    final documents =
                        ref.watch(taxDocumentProvider).asData?.value ??
                            const <TaxDocument>[];
                    final vaultSummary =
                        DocumentVaultSummary.fromDocuments(documents);
                    final activeYear = ref.watch(activeTaxYearProvider);
                    final docPercent = documentReadinessPercent(checklist);
                    final next = buildNextBestAction(
                      diagnosticComplete: true,
                      documentPercent: docPercent,
                      result: result,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PremiumHeader(
                            eyebrow: '${activeYear.fyLabel} story',
                            title:
                                '${profile.name.isEmpty ? 'Your' : '${profile.name.split(' ').first}’s'} tax story',
                            body:
                                'A clear narrative of income, regime insight, proof readiness, assumptions, and next steps.',
                            icon: Icons.auto_stories_outlined,
                            trailing: TaxRuleBadge(result: result),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: ArthMetricCard(
                                  label: 'Income',
                                  value: formatRupeesCompact(profile.annualCTC),
                                  helper: profile.employmentType.name,
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ArthMetricCard(
                                  label: 'Docs',
                                  value: '$docPercent%',
                                  helper: 'proof readiness',
                                  icon: Icons.folder_copy_outlined,
                                  color: PaycheckColors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ArthMetricCard(
                            label: 'Best current route',
                            value: result.betterRegimeLabel,
                            helper:
                                'Estimated advantage ${formatRupeesCompact(result.regimeSavings.round())}',
                            icon: Icons.compare_arrows_rounded,
                            color: PaycheckColors.gold,
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Vault map',
                            child: Column(
                              children: [
                                StoryPanel(
                                  icon: Icons.folder_special_outlined,
                                  title:
                                      '${vaultSummary.active} active proof(s)',
                                  body:
                                      '$docPercent% proof readiness. ${vaultSummary.needsReview} document(s) need review and ${vaultSummary.ready} are confirmed.',
                                  color: vaultSummary.needsReview > 0
                                      ? PaycheckColors.amber
                                      : PaycheckColors.teal,
                                  trailing: IconButton(
                                    tooltip: 'Open Vault',
                                    onPressed: () => context.push('/documents'),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                StoryPanel(
                                  icon: Icons.account_balance_outlined,
                                  title: 'AIS / 26AS check',
                                  body:
                                      'Use official records to compare TDS, interest, dividends, and reported income before filing handoff.',
                                  color: PaycheckColors.info,
                                  trailing: IconButton(
                                    tooltip: 'Open guide',
                                    onPressed: () => context.push('/ais-guide'),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Top proof and gap signals',
                            child: PremiumGlassPanel(
                              child: Column(
                                children: [
                                  _StoryLine(
                                    icon: Icons.verified_outlined,
                                    title: 'Confidence',
                                    body:
                                        '${result.confidenceScore}% • ${result.confidenceLabel}',
                                  ),
                                  const Divider(color: PaycheckColors.divider),
                                  _StoryLine(
                                    icon: Icons.savings_outlined,
                                    title: 'Deduction opportunity',
                                    body:
                                        '${formatRupeesCompact(result.deductionOpportunity)} opportunity, ${formatRupeesCompact(result.estimatedTaxBenefit)} estimated tax benefit.',
                                  ),
                                  const Divider(color: PaycheckColors.divider),
                                  _StoryLine(
                                    icon: Icons.folder_copy_outlined,
                                    title: 'Proof readiness',
                                    body:
                                        '$docPercent% of your document checklist is ready.',
                                  ),
                                  const Divider(color: PaycheckColors.divider),
                                  _StoryLine(
                                    icon: Icons.warning_amber_outlined,
                                    title: 'Assumptions',
                                    body: result.assumptions.isEmpty
                                        ? 'No major estimation warnings are visible.'
                                        : '${result.assumptions.length} input(s) can improve this story.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Next move',
                            child: PremiumGlassPanel(
                              tint: PaycheckColors.teal,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(next.icon,
                                      color: PaycheckColors.gold, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(next.title,
                                            style: PaycheckType.h3()),
                                        const SizedBox(height: 4),
                                        Text(
                                          next.body,
                                          style: PaycheckType.caption(
                                            color: PaycheckColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                          style: AppButtons.outlineGold,
                                          onPressed: () =>
                                              context.push(next.route),
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                          ),
                                          label: Text(next.cta),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _StoryLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PaycheckColors.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
