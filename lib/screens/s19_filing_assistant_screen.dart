import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tax_readiness.dart';
import '../providers/entitlement_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';
import '../widgets/tax_rule_badge.dart';

class FilingAssistantScreen extends ConsumerWidget {
  const FilingAssistantScreen({super.key});

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
            eyebrow: 'Actions',
            title: 'Filing Assistant',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/action-plan');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
              color: PaycheckColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Checking filing readiness',
                insights: ['Preparing your handoff checklist.'],
              ),
              error: (_, __) => const _FilingEmpty(),
              data: (complete) {
                if (!complete) return const _FilingEmpty();
                final resultAsync = ref.watch(taxResultProvider);
                return resultAsync.when(
                  loading: () => const ArthLoadingPanel(
                    title: 'Building filing assistant',
                    insights: ['Reviewing tax result and proof readiness.'],
                  ),
                  error: (_, __) => RetryErrorState(
                    message: 'Could not build the filing assistant',
                    onRetry: () => ref.invalidate(taxResultProvider),
                  ),
                  data: (result) {
                    final checklist = ref.watch(documentChecklistProvider);
                    final entitlement = ref.watch(entitlementProvider);
                    final readyDocs = completedDocumentCount(checklist);
                    final documentsAsync = ref.watch(taxDocumentProvider);

                    return documentsAsync.when(
                      loading: () => const ArthLoadingPanel(
                        title: 'Checking document vault',
                        insights: ['Confirming uploaded proof status.'],
                      ),
                      error: (_, __) => RetryErrorState(
                        message:
                            'Could not load document readiness. Retry before using the filing pack.',
                        onRetry: () => ref.invalidate(taxDocumentProvider),
                      ),
                      data: (documents) {
                        final confirmedDocs =
                            documents.where((doc) => doc.parsed).length;
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
                                      icon: Icons.inventory_2_outlined,
                                      label: 'Filing prep, not ITR submission',
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'CA-ready Filing Pack',
                                      style: PaycheckType.h1(),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Everything you would hand to a CA.',
                                      style: PaycheckType.body(
                                        color: PaycheckColors.textSecondary,
                                      ),
                                    ),
                                    const ArthDisclosure(
                                      label: 'What the pack contains',
                                      detail:
                                          'Your numbers, documents, assumptions and missing items, ready for a CA, an employer portal or the official tax portal.',
                                    ),
                                    const SizedBox(height: 16),
                                    TaxRuleBadge(result: result),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ArthSection(
                                title: 'Readiness map',
                                child: PremiumGlassPanel(
                                  child: Column(
                                    children: [
                                      _ReadinessRow(
                                        icon: Icons.verified_outlined,
                                        title: 'Calculation confidence',
                                        body:
                                            '${result.confidenceScore}% • ${result.confidenceLabel}',
                                        ready: result.confidenceScore >= 85,
                                      ),
                                      const Divider(
                                          color: PaycheckColors.divider),
                                      _ReadinessRow(
                                        icon: Icons.folder_copy_outlined,
                                        title: 'Proof checklist',
                                        body:
                                            '$readyDocs/${taxDocumentItems.length} proof categories marked ready',
                                        ready: readyDocs >=
                                            taxDocumentItems.length,
                                      ),
                                      const Divider(
                                          color: PaycheckColors.divider),
                                      _ReadinessRow(
                                        icon: Icons.document_scanner_outlined,
                                        title: 'Confirmed parsed documents',
                                        body:
                                            '$confirmedDocs confirmed. Upload Form 16 as a text PDF for deterministic parsing.',
                                        ready: confirmedDocs > 0,
                                      ),
                                      const Divider(
                                          color: PaycheckColors.divider),
                                      const _ReadinessRow(
                                        icon: Icons.account_balance_outlined,
                                        title: 'AIS / 26AS review',
                                        body:
                                            'Use the guide to check tax credits and reported income before filing.',
                                        ready: false,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              ArthSection(
                                title: 'Pack contents',
                                child: PremiumGlassPanel(
                                  tint: entitlement.isPremiumDemo
                                      ? PaycheckColors.gold
                                      : PaycheckColors.textSecondary,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TrustBadge(
                                        icon: entitlement.isPremiumDemo
                                            ? Icons.workspace_premium_outlined
                                            : Icons.lock_outline_rounded,
                                        label: entitlement.isPremiumDemo
                                            ? 'Premium demo unlocked'
                                            : 'Premium demo locked',
                                        color: entitlement.isPremiumDemo
                                            ? PaycheckColors.gold
                                            : PaycheckColors.textSecondary,
                                      ),
                                      const SizedBox(height: 12),
                                      const _PackLine(
                                        title: 'Tax Dossier',
                                        body:
                                            'Income profile, regime insight, deduction opportunity, tax benefit, and assumptions.',
                                      ),
                                      const _PackLine(
                                        title: 'Proof bundle checklist',
                                        body:
                                            'What is ready, what is uploaded, and what still needs collection.',
                                      ),
                                      const _PackLine(
                                        title: 'Filing handoff notes',
                                        body:
                                            'Clear reminders for CA/portal review. No official ITR filing claim.',
                                      ),
                                      const SizedBox(height: 12),
                                      if (entitlement.isPremiumDemo)
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            OutlinedButton.icon(
                                              style: AppButtons.outlineGold,
                                              onPressed: () =>
                                                  context.push('/tax-dossier'),
                                              icon: const Icon(
                                                Icons.assignment_outlined,
                                              ),
                                              label: const Text('Open dossier'),
                                            ),
                                            OutlinedButton.icon(
                                              style: AppButtons.outlineGold,
                                              onPressed: () =>
                                                  context.push('/documents'),
                                              icon: const Icon(
                                                Icons.folder_special_outlined,
                                              ),
                                              label: const Text('Review docs'),
                                            ),
                                          ],
                                        )
                                      else
                                        OutlinedButton.icon(
                                          style: AppButtons.outlineGold,
                                          onPressed: () =>
                                              context.go('/profile'),
                                          icon: const Icon(
                                            Icons.workspace_premium_outlined,
                                          ),
                                          label: const Text(
                                            'Enable demo in Profile',
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilingEmpty extends StatelessWidget {
  const _FilingEmpty();

  @override
  Widget build(BuildContext context) {
    return ArthStatePanel(
      icon: Icons.inventory_2_outlined,
      title: 'Prepare your filing pack',
      message: 'Complete the diagnostic first.',
      detail:
          'ARTH then maps your result, proofs and assumptions into a filing handoff checklist.',
      actionLabel: 'Start diagnostic',
      onAction: () => context.go('/questions'),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool ready;

  const _ReadinessRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : icon,
            color: ready ? PaycheckColors.success : PaycheckColors.gold,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  body,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackLine extends StatelessWidget {
  final String title;
  final String body;

  const _PackLine({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_rounded,
            color: PaycheckColors.teal,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  body,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
