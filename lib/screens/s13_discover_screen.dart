import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../models/tax_document.dart';
import '../models/tax_readiness.dart';
import '../providers/account_profile_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/tax_year_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeAsync = ref.watch(completedTaxProfileProvider);

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 0,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Home',
            title: 'ARTH',
            actions: [
              IconButton(
                tooltip: 'Help Center',
                onPressed: () => context.push('/help'),
                icon: const Icon(Icons.support_agent_rounded),
                color: AppColors.textSecondary,
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => context.go('/profile'),
                icon: const Icon(Icons.person_outline_rounded),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Opening Tax OS',
                insights: ['Checking diagnostic and readiness state.'],
              ),
              error: (_, __) => const _TaxOsHome(complete: false),
              data: (complete) => _TaxOsHome(complete: complete),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxOsHome extends ConsumerWidget {
  final bool complete;

  const _TaxOsHome({required this.complete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(documentChecklistProvider);
    final docPercent = documentReadinessPercent(checklist);
    final documents =
        ref.watch(taxDocumentProvider).asData?.value ?? const <TaxDocument>[];
    final vaultSummary = DocumentVaultSummary.fromDocuments(documents);
    final panPresent =
        ref.watch(accountProfileProvider).asData?.value?.pan.present ?? false;
    final entitlement = ref.watch(entitlementProvider);
    final activeYear = ref.watch(activeTaxYearProvider);
    final result = complete ? ref.watch(taxResultProvider).asData?.value : null;
    final readiness = _readinessScore(
      diagnosticComplete: complete,
      docPercent: docPercent,
      panPresent: panPresent,
      confidenceScore: result?.confidenceScore,
    );
    final next = buildNextBestAction(
      diagnosticComplete: complete,
      documentPercent: docPercent,
      panPresent: panPresent,
      result: result,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumHeader(
            eyebrow: 'Private Tax OS',
            title: 'Readiness cockpit',
            body: complete
                ? 'Gaps, proof vault, assumptions, AIS checks, and CA-ready handoff in one calm view.'
                : 'Explore first. Start the diagnostic when ready. PAN and document uploads stay optional.',
            icon: Icons.home_work_outlined,
            trailing: IconButton(
              tooltip: 'Tax Story',
              style: IconButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
              ),
              onPressed: () => context.push('/tax-story'),
              icon: const Icon(Icons.auto_stories_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ArthMetricCard(
                  label: 'Readiness',
                  value: '$readiness%',
                  helper: result?.confidenceLabel ??
                      (complete ? 'diagnostic active' : 'diagnostic pending'),
                  icon: Icons.speed_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ArthMetricCard(
                  label: 'Vault',
                  value: '${vaultSummary.needsReview}',
                  helper: 'needs review',
                  icon: Icons.folder_special_outlined,
                  color: vaultSummary.needsReview > 0
                      ? AppColors.amber
                      : AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ActionDock(
            primaryLabel: next.cta,
            primaryIcon: next.icon,
            onPrimary: () => context.go(next.route),
            secondaryLabel: 'Open Vault',
            secondaryIcon: Icons.folder_special_outlined,
            onSecondary: () => context.push('/documents'),
          ),
          const SizedBox(height: 18),
          _NextBestActionCard(action: next),
          const SizedBox(height: 20),
          _QuickActionStrip(complete: complete),
          const SizedBox(height: 20),
          ArthSection(
            title: 'Seasonal calendar',
            child: Column(
              children: [
                _CalendarTile(
                  icon: Icons.event_note_outlined,
                  title: 'Proof collection',
                  date: activeYear.fyLabel,
                  body:
                      'Prepare salary, rent, insurance, loan, and 80C proofs.',
                  onTap: () => context.push('/tax-calendar'),
                ),
                const SizedBox(height: 10),
                _CalendarTile(
                  icon: Icons.account_balance_outlined,
                  title: 'AIS / 26AS review',
                  date: 'Before filing',
                  body: 'Check official tax credits and reported income.',
                  onTap: () => context.push('/ais-guide'),
                ),
                const SizedBox(height: 10),
                _CalendarTile(
                  icon: Icons.task_alt_rounded,
                  title: 'Filing handoff',
                  date: 'By Jul 31',
                  body: 'Use official portal, employer partner, or CA.',
                  onTap: () => context.push('/filing-assistant'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ArthSection(
            title: 'Everything tax',
            child: Column(
              children: [
                _ModuleTile(
                  icon: Icons.auto_stories_outlined,
                  title: 'My Tax Story',
                  body: 'Premium summary of your tax readiness and next move.',
                  onTap: () => context.push('/tax-story'),
                ),
                const SizedBox(height: 10),
                _ModuleTile(
                  icon: Icons.science_outlined,
                  title: 'What-if simulator',
                  body: 'Try 80C, NPS, and 80D changes without mutating data.',
                  onTap: () => context.push('/tax-simulator'),
                ),
                const SizedBox(height: 10),
                _ModuleTile(
                  icon: Icons.folder_special_outlined,
                  title: 'Document Vault',
                  body:
                      '$docPercent% proof readiness. ${vaultSummary.needsReview} item(s) need review.',
                  onTap: () => context.push('/documents'),
                ),
                const SizedBox(height: 10),
                _ModuleTile(
                  icon: Icons.account_balance_outlined,
                  title: 'AIS & 26AS guide',
                  body: 'Know what to verify in official tax records.',
                  onTap: () => context.push('/ais-guide'),
                ),
                const SizedBox(height: 10),
                _ModuleTile(
                  icon: Icons.assignment_outlined,
                  title: 'Tax Dossier',
                  body: 'In-app summary of profile, gaps, proofs, and handoff.',
                  onTap: () => context.push('/tax-dossier'),
                ),
                const SizedBox(height: 10),
                _PremiumModuleTile(
                  icon: Icons.document_scanner_outlined,
                  title: 'Document Intelligence',
                  body: entitlement.isPremiumDemo
                      ? 'Premium demo unlocked. Upload Form 16, AIS, or 26AS for deterministic parsing readiness.'
                      : 'Premium demo. Form 16, AIS, and 26AS parsing plus mismatch checklist.',
                  unlocked: entitlement.isPremiumDemo,
                  onTap: () => context.push('/documents'),
                ),
                const SizedBox(height: 10),
                _PremiumModuleTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'CA-ready Filing Pack',
                  body: entitlement.isPremiumDemo
                      ? 'Premium demo unlocked. Build a dossier and proof handoff checklist.'
                      : 'Premium demo. Exportable dossier, proof bundle, and filing handoff checklist.',
                  unlocked: entitlement.isPremiumDemo,
                  onTap: () => context.push('/filing-assistant'),
                ),
                const SizedBox(height: 10),
                _ModuleTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Help Center',
                  body: 'Report issues, ask questions, or get data help.',
                  onTap: () => context.push('/help'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _readinessScore({
    required bool diagnosticComplete,
    required int docPercent,
    required bool panPresent,
    int? confidenceScore,
  }) {
    final diagnostic = diagnosticComplete ? 32 : 0;
    final docs = (docPercent * 0.28).round();
    final identity = panPresent ? 8 : 0;
    final confidence = confidenceScore == null
        ? 0
        : (confidenceScore.clamp(0, 100) * 0.25).round();
    const guideBase = 12;
    return (diagnostic + docs + identity + confidence + guideBase)
        .clamp(0, 100)
        .toInt();
  }
}

class _PremiumModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool unlocked;
  final VoidCallback onTap;

  const _PremiumModuleTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.unlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      tint: unlocked ? AppColors.gold : AppColors.textSecondary,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon,
            color: unlocked ? AppColors.gold : AppColors.textSecondary),
        title: Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.bodyMedium())),
            const SizedBox(width: 8),
            TrustBadge(
              icon: unlocked
                  ? Icons.workspace_premium_outlined
                  : Icons.lock_outline_rounded,
              label: unlocked ? 'Premium demo' : 'Locked',
              color: unlocked ? AppColors.gold : AppColors.textSecondary,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            body,
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
        ),
        trailing: Icon(
          unlocked ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
        ),
        onTap: unlocked ? onTap : null,
      ),
    );
  }
}

class _NextBestActionCard extends StatelessWidget {
  final NextBestAction action;

  const _NextBestActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'Next best action',
      child: PremiumGlassPanel(
        tint: AppColors.teal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(action.icon, color: AppColors.gold, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TrustBadge(
                    icon: Icons.bolt_rounded,
                    label: 'Guided',
                    color: AppColors.teal,
                  ),
                  const SizedBox(height: 10),
                  Text(action.title, style: AppTextStyles.h3()),
                  const SizedBox(height: 5),
                  Text(
                    action.body,
                    style:
                        AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: AppButtons.outlineGold,
                    onPressed: () => context.push(action.route),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(action.cta),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionStrip extends StatelessWidget {
  final bool complete;

  const _QuickActionStrip({required this.complete});

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        children: [
          _MiniAction(
            icon: Icons.tune_rounded,
            label: 'Accuracy',
            onTap: () => context.push(
              complete ? '/accuracy-coach' : '/questions',
            ),
          ),
          _MiniAction(
            icon: Icons.science_outlined,
            label: 'What-if',
            onTap: () => context.push(
              complete ? '/tax-simulator' : '/questions',
            ),
          ),
          _MiniAction(
            icon: Icons.event_available_outlined,
            label: 'Calendar',
            onTap: () => context.push('/tax-calendar'),
          ),
          _MiniAction(
            icon: Icons.support_agent_rounded,
            label: 'Help',
            onTap: () => context.push('/help'),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.pill,
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: AppRadius.pill,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.gold, size: 19),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.micro()),
          ],
        ),
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String date;
  final String body;
  final VoidCallback onTap;

  const _CalendarTile({
    required this.icon,
    required this.title,
    required this.date,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.card,
      onTap: onTap,
      child: PremiumGlassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.teal, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(title, style: AppTextStyles.h3())),
                      const SizedBox(width: 8),
                      Text(date,
                          style: AppTextStyles.micro(color: AppColors.gold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style:
                        AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _ModuleTile({
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
        leading: Icon(icon, color: AppColors.gold),
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
