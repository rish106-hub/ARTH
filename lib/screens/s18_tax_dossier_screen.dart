import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class TaxDossierScreen extends ConsumerWidget {
  const TaxDossierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeAsync = ref.watch(completedTaxProfileProvider);
    final checklist = ref.watch(documentChecklistProvider);
    final account = ref.watch(accountProfileProvider).asData?.value;
    final readyDocs = completedDocumentCount(checklist);
    final docPercent = documentReadinessPercent(checklist);

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
            eyebrow: 'Tax OS',
            title: 'Tax Dossier',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Opening dossier',
                insights: ['Checking diagnostic status.'],
              ),
              error: (_, __) => const _DossierEmpty(),
              data: (complete) {
                if (!complete) return const _DossierEmpty();
                final resultAsync = ref.watch(taxResultProvider);
                return resultAsync.when(
                  loading: () => const ArthLoadingPanel(
                    title: 'Building dossier',
                    insights: ['Summarising your tax readiness.'],
                  ),
                  error: (_, __) => RetryErrorState(
                    message: 'Could not load your Tax Dossier.',
                    onRetry: () => ref.invalidate(taxResultProvider),
                  ),
                  data: (result) {
                    final profile = ref.watch(userProfileProvider);
                    final panPresent = account?.pan.present ?? false;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PremiumGlassPanel(
                            elevated: true,
                            borderRadius: BorderRadius.circular(28),
                            tint: AppColors.gold,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const TrustBadge(
                                  icon: Icons.assignment_outlined,
                                  label: 'In-app summary',
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Private Tax Readiness Dossier',
                                  style: AppTextStyles.h1(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'A single view of your income profile, regime insight, missing proofs, and filing handoff readiness.',
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
                                  label: 'Deduction opportunity',
                                  value: formatRupeesCompact(
                                      result.deductionOpportunity),
                                  helper:
                                      'Est. benefit ${formatRupeesCompact(result.estimatedTaxBenefit)}',
                                  icon: Icons.savings_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ArthMetricCard(
                                  label: 'Docs',
                                  value: '$docPercent%',
                                  helper:
                                      '$readyDocs/${taxDocumentItems.length} ready',
                                  icon: Icons.folder_copy_outlined,
                                  color: AppColors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Summary',
                            child: PremiumGlassPanel(
                              child: Column(
                                children: [
                                  _DossierRow(
                                    icon: Icons.gavel_outlined,
                                    title: 'Rule version',
                                    body:
                                        '${result.ruleSetLabel}, ${result.assessmentYear}.',
                                  ),
                                  const Divider(color: AppColors.divider),
                                  _DossierRow(
                                    icon: Icons.person_outline_rounded,
                                    title: 'Income profile',
                                    body:
                                        '${profile.employmentType.name}, ${formatRupeesCompact(profile.annualCTC)} CTC, ${profile.city}',
                                  ),
                                  const Divider(color: AppColors.divider),
                                  _DossierRow(
                                    icon: Icons.compare_arrows_rounded,
                                    title: 'Regime insight',
                                    body:
                                        '${result.betterRegime.name} regime currently looks better by ${formatRupeesCompact(result.regimeSavings.round())}.',
                                  ),
                                  const Divider(color: AppColors.divider),
                                  _DossierRow(
                                    icon: Icons.badge_outlined,
                                    title: 'PAN status',
                                    body: panPresent
                                        ? 'Optional PAN vault is active with masked display only.'
                                        : 'PAN is not required. Add it later from Profile if useful.',
                                  ),
                                  const Divider(color: AppColors.divider),
                                  _DossierRow(
                                    icon: Icons.verified_outlined,
                                    title: 'Filing handoff',
                                    body:
                                        'Prepare proofs, review AIS/26AS, then file via official portal, employer partner, or CA.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ArthSection(
                            title: 'Next actions',
                            child: Column(
                              children: [
                                _DossierAction(
                                  icon: Icons.checklist_rounded,
                                  title: 'Open action plan',
                                  body:
                                      'Close deduction gaps from highest-value to easiest.',
                                  onTap: () => context.go('/action-plan'),
                                ),
                                const SizedBox(height: 10),
                                _DossierAction(
                                  icon: Icons.folder_special_outlined,
                                  title: 'Update document checklist',
                                  body:
                                      'Mark proofs ready without uploading files.',
                                  onTap: () => context.push('/documents'),
                                ),
                                const SizedBox(height: 10),
                                _DossierAction(
                                  icon: Icons.account_balance_outlined,
                                  title: 'Read AIS & 26AS guide',
                                  body:
                                      'Know what official data to verify before filing.',
                                  onTap: () => context.push('/ais-guide'),
                                ),
                              ],
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

class _DossierEmpty extends StatelessWidget {
  const _DossierEmpty();

  @override
  Widget build(BuildContext context) {
    return ArthStatePanel(
      icon: Icons.assignment_outlined,
      title: 'Build your Tax Dossier',
      message:
          'Complete the diagnostic once. ARTH will turn it into a private tax readiness summary.',
      actionLabel: 'Start diagnostic',
      onAction: () => context.go('/questions'),
    );
  }
}

class _DossierRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _DossierRow({
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

class _DossierAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _DossierAction({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.teal),
        title: Text(title, style: AppTextStyles.bodyMedium()),
        subtitle: Text(
          body,
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
