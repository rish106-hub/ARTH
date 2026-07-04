import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../models/tax_readiness.dart';
import '../providers/account_profile_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
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
        selectedIndex: 0,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/discover');
              break;
            case 1:
              context.go('/action-plan');
              break;
            case 2:
              context.go('/progress');
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
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
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Opening Tax Story',
                insights: ['Preparing your private summary.'],
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
                        'Complete the diagnostic once to generate a private tax-readiness story.',
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
                    final docPercent = documentReadinessPercent(checklist);
                    final panPresent = ref
                            .watch(accountProfileProvider)
                            .asData
                            ?.value
                            ?.pan
                            .present ??
                        false;
                    final next = buildNextBestAction(
                      diagnosticComplete: true,
                      documentPercent: docPercent,
                      panPresent: panPresent,
                      result: result,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PremiumGlassPanel(
                            elevated: true,
                            borderRadius: BorderRadius.circular(30),
                            tint: AppColors.gold,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const TrustBadge(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Private summary',
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '${profile.name.isEmpty ? 'Your' : '${profile.name.split(' ').first}’s'} tax readiness story',
                                  style: AppTextStyles.h1(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'A clean interview-ready view of what ARTH knows, what it assumes, and what you should do next.',
                                  style: AppTextStyles.body(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TaxRuleBadge(result: result),
                              ],
                            ),
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
                                  color: AppColors.teal,
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
                            color: AppColors.gold,
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
                                  const Divider(color: AppColors.divider),
                                  _StoryLine(
                                    icon: Icons.savings_outlined,
                                    title: 'Deduction opportunity',
                                    body:
                                        '${formatRupeesCompact(result.deductionOpportunity)} opportunity, ${formatRupeesCompact(result.estimatedTaxBenefit)} estimated tax benefit.',
                                  ),
                                  const Divider(color: AppColors.divider),
                                  _StoryLine(
                                    icon: Icons.badge_outlined,
                                    title: 'PAN vault',
                                    body: panPresent
                                        ? 'Optional PAN vault is active and masked.'
                                        : 'PAN is optional and not required for this story.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Next move',
                            child: PremiumGlassPanel(
                              tint: AppColors.teal,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(next.icon,
                                      color: AppColors.gold, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(next.title,
                                            style: AppTextStyles.h3()),
                                        const SizedBox(height: 4),
                                        Text(
                                          next.body,
                                          style: AppTextStyles.caption(
                                            color: AppColors.textSecondary,
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
          Icon(icon, color: AppColors.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 3),
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
