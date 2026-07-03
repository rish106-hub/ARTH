import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tax_readiness.dart';
import '../providers/account_profile_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_number.dart';
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
        onTap: (i) {
          switch (i) {
            case 0:
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
    final panPresent =
        ref.watch(accountProfileProvider).asData?.value?.pan.present ?? false;
    final entitlement = ref.watch(entitlementProvider);
    final result = complete ? ref.watch(taxResultProvider).asData?.value : null;
    final readiness = _readinessScore(
      diagnosticComplete: complete,
      docPercent: docPercent,
      panPresent: panPresent,
      confidenceScore: result?.confidenceScore,
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
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TrustBadge(
                      icon: Icons.shield_outlined,
                      label: 'Privacy-first',
                    ),
                    TrustBadge(
                      icon: Icons.lock_outline_rounded,
                      label: 'Encrypted documents',
                      color: AppColors.teal,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Private Tax Readiness Cockpit',
                    style: AppTextStyles.h1()),
                const SizedBox(height: 10),
                Text(
                  complete
                      ? 'Track gaps, proofs, deadlines, AIS checks, and handoff readiness from one place.'
                      : 'Explore the app first. Start a 3-minute diagnostic when ready. PAN and document uploads are optional.',
                  style: AppTextStyles.body(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: AppButtons.primaryGold,
                        onPressed: () => context.go(
                          complete ? '/gap-reveal' : '/questions',
                        ),
                        icon: Icon(
                          complete
                              ? Icons.radar_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          complete ? 'Open cockpit' : 'Start diagnostic',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Tax Dossier',
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                      ),
                      onPressed: () => context.push('/tax-dossier'),
                      icon: const Icon(Icons.assignment_outlined),
                    ),
                  ],
                ),
              ],
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
                  label: 'PAN',
                  value: panPresent ? 'Saved' : 'Optional',
                  helper: 'Profile vault',
                  icon: Icons.badge_outlined,
                  color: panPresent ? AppColors.success : AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (complete) const _CompletedSummary() else const _FreshUserPlan(),
          const SizedBox(height: 20),
          ArthSection(
            title: 'Seasonal calendar',
            child: Column(
              children: const [
                _CalendarTile(
                  icon: Icons.event_note_outlined,
                  title: 'Proof collection',
                  date: 'Now to Mar 31',
                  body:
                      'Prepare salary, rent, insurance, loan, and 80C proofs.',
                ),
                SizedBox(height: 10),
                _CalendarTile(
                  icon: Icons.account_balance_outlined,
                  title: 'AIS / 26AS review',
                  date: 'Before filing',
                  body: 'Check official tax credits and reported income.',
                ),
                SizedBox(height: 10),
                _CalendarTile(
                  icon: Icons.task_alt_rounded,
                  title: 'Filing handoff',
                  date: 'By Jul 31',
                  body: 'Use official portal, employer partner, or CA.',
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
                  icon: Icons.folder_special_outlined,
                  title: 'Document checklist',
                  body:
                      '$docPercent% proof readiness. Encrypted upload optional.',
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
                  icon: Icons.inventory_2_outlined,
                  title: 'Filing Assistant',
                  body:
                      'Map your result, proofs, and assumptions into a CA/portal handoff checklist.',
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

class _CompletedSummary extends ConsumerWidget {
  const _CompletedSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);
    return resultAsync.when(
      loading: () => const PremiumSkeleton(height: 122),
      error: (_, __) => _ModuleTile(
        icon: Icons.error_outline_rounded,
        title: 'Cockpit temporarily unavailable',
        body: 'Retry from the cockpit when network is stable.',
        onTap: () => context.go('/gap-reveal'),
      ),
      data: (result) => ArthSection(
        title: 'Next best action',
        child: PremiumGlassPanel(
          tint: AppColors.teal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrustBadge(
                      icon: Icons.verified_outlined,
                      label: '${result.confidenceScore}% confidence',
                      color: result.confidenceScore >= 85
                          ? AppColors.success
                          : AppColors.gold,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      result.assumptions.isNotEmpty
                          ? 'Improve calculation accuracy'
                          : result.gaps.isEmpty
                              ? 'Keep documents ready'
                              : result.gaps.first.title,
                      style: AppTextStyles.h3(),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      result.assumptions.isNotEmpty
                          ? result.assumptions.first.detail
                          : result.gaps.isEmpty
                              ? 'No major gap found. Maintain proof readiness and AIS review.'
                              : 'Potential gap value: ${formatRupeesCompact(result.gaps.first.gapAmount)}.',
                      style:
                          AppTextStyles.caption(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: AppButtons.outlineGold,
                      onPressed: () => context.go(
                        result.assumptions.isNotEmpty
                            ? '/profile'
                            : '/action-plan',
                      ),
                      icon: Icon(
                        result.assumptions.isNotEmpty
                            ? Icons.tune_rounded
                            : Icons.checklist_rounded,
                      ),
                      label: Text(
                        result.assumptions.isNotEmpty
                            ? 'Add exact inputs'
                            : 'Open actions',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreshUserPlan extends StatelessWidget {
  const _FreshUserPlan();

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'Start here',
      child: PremiumGlassPanel(
        child: Column(
          children: [
            const _PlanRow(
              icon: Icons.route_rounded,
              title: 'Run 3-minute diagnostic',
              body:
                  'Answer salary, rent, deduction, loan, and insurance basics.',
            ),
            const Divider(color: AppColors.divider),
            const _PlanRow(
              icon: Icons.folder_copy_outlined,
              title: 'Prepare proofs',
              body:
                  'Use the checklist before collecting or sharing files anywhere.',
            ),
            const Divider(color: AppColors.divider),
            const _PlanRow(
              icon: Icons.account_balance_outlined,
              title: 'Review official records',
              body: 'Use AIS and 26AS guide before filing.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.push('/welcome'),
                child: const Text('See onboarding story'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PlanRow({
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

class _CalendarTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String date;
  final String body;

  const _CalendarTile({
    required this.icon,
    required this.title,
    required this.date,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
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
