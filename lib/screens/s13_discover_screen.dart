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
        onTap: (index) => goToArthTab(context, index),
      ),
      child: completeAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Opening ARTH',
          insights: ['Preparing your tax position.'],
        ),
        error: (_, __) => const _ArthHome(complete: false),
        data: (complete) => _ArthHome(complete: complete),
      ),
    );
  }
}

class _ArthHome extends ConsumerWidget {
  final bool complete;

  const _ArthHome({required this.complete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final checklist = ref.watch(documentChecklistProvider);
    final documentPercent = documentReadinessPercent(checklist);
    final documents =
        ref.watch(taxDocumentProvider).asData?.value ?? const <TaxDocument>[];
    final vaultSummary = DocumentVaultSummary.fromDocuments(documents);
    final year = ref.watch(activeTaxYearProvider);
    final result = complete ? ref.watch(taxResultProvider).asData?.value : null;
    final readiness = _readinessScore(
      diagnosticComplete: complete,
      documentPercent: documentPercent,
      confidenceScore: result?.confidenceScore,
    );
    final next = buildNextBestAction(
      diagnosticComplete: complete,
      documentPercent: documentPercent,
      result: result,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HomeHeader(
            name: profile.name,
            onHelp: () => context.push('/help'),
            onProfile: () => context.go('/profile'),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          sliver: SliverList.list(
            children: [
              _PositionSummary(
                complete: complete,
                readiness: readiness,
                opportunity: result?.deductionOpportunity ?? 0,
                yearLabel: year.fyLabel,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: AppButtons.primaryGold,
                  onPressed: () => context.go(
                    complete ? '/gap-reveal' : '/questions',
                  ),
                  icon: Icon(
                    complete
                        ? Icons.insights_rounded
                        : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                  label: Text(
                    complete
                        ? 'Open my tax position'
                        : 'Start 3-minute tax check',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _JourneyProgress(
                complete: complete,
                documentPercent: documentPercent,
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: 'Next move'),
              const SizedBox(height: 10),
              _NextMoveTile(
                action: next,
                onTap: () => context.push(next.route),
              ),
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Bring in your tax data',
                helper: '${vaultSummary.needsReview} need review',
              ),
              const SizedBox(height: 10),
              _DataImportPanel(
                onManual: () => context.push('/documents'),
                onDigiLocker: () => _showDigiLockerStatus(context),
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: 'Explore ARTH'),
              const SizedBox(height: 4),
              _ToolList(
                tools: [
                  _Tool(
                    icon: Icons.folder_copy_outlined,
                    title: 'Document Vault',
                    body: 'Keep proofs and filing records together.',
                    onTap: () => context.push('/documents'),
                  ),
                  _Tool(
                    icon: Icons.auto_stories_outlined,
                    title: 'My Tax Story',
                    body: 'Your year explained in plain language.',
                    onTap: () => context.push('/tax-story'),
                  ),
                  _Tool(
                    icon: Icons.science_outlined,
                    title: 'What-if simulator',
                    body: 'Test 80C, NPS and 80D moves.',
                    onTap: () => context.push(
                      complete ? '/tax-simulator' : '/questions',
                    ),
                  ),
                  _Tool(
                    icon: Icons.assignment_outlined,
                    title: 'Tax Dossier',
                    body: 'Profile, opportunities and proof status.',
                    onTap: () => context.push('/tax-dossier'),
                  ),
                  _Tool(
                    icon: Icons.account_balance_outlined,
                    title: 'AIS & 26AS guide',
                    body: 'Check official income and tax credits.',
                    onTap: () => context.push('/ais-guide'),
                  ),
                  _Tool(
                    icon: Icons.calendar_month_outlined,
                    title: 'Tax calendar',
                    body: 'Proof, planning and filing dates.',
                    onTap: () => context.push('/tax-calendar'),
                  ),
                  _Tool(
                    icon: Icons.support_agent_outlined,
                    title: 'Help Center',
                    body: 'Get help with ARTH and your data.',
                    onTap: () => context.push('/help'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _readinessScore({
    required bool diagnosticComplete,
    required int documentPercent,
    int? confidenceScore,
  }) {
    if (!diagnosticComplete) return 0;
    final diagnostic = 55;
    final documents = (documentPercent * 0.30).round();
    final confidence = confidenceScore == null
        ? 0
        : (confidenceScore.clamp(0, 100) * 0.15).round();
    return (diagnostic + documents + confidence).clamp(0, 100).toInt();
  }

  void _showDigiLockerStatus(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DigiLocker connection is being prepared.'),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final String name;
  final VoidCallback onHelp;
  final VoidCallback onProfile;

  const _HomeHeader({
    required this.name,
    required this.onHelp,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    final firstName = trimmedName.isEmpty ? null : trimmedName.split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName == null || firstName.isEmpty
                      ? 'YOUR TAX YEAR'
                      : 'HELLO, ${firstName.toUpperCase()}',
                  style: AppTextStyles.sectionLabel(color: AppColors.gold),
                ),
                const SizedBox(height: 3),
                Text('ARTH', style: AppTextStyles.h2()),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Help Center',
            onPressed: onHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: onProfile,
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _PositionSummary extends StatelessWidget {
  final bool complete;
  final int readiness;
  final int opportunity;
  final String yearLabel;

  const _PositionSummary({
    required this.complete,
    required this.readiness,
    required this.opportunity,
    required this.yearLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: complete ? readiness / 100 : 0.06,
                  strokeWidth: 7,
                  backgroundColor: AppColors.bgSurface,
                  color: complete ? AppColors.success : AppColors.amber,
                  strokeCap: StrokeCap.round,
                ),
                Text(
                  complete ? '$readiness' : '—',
                  style: AppTextStyles.h3(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Readiness cockpit', style: AppTextStyles.h3()),
                const SizedBox(height: 5),
                Text(
                  complete
                      ? '${formatRupeesCompact(opportunity)} in deduction opportunities mapped.'
                      : 'Your tax position has not been mapped yet.',
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 7),
                Text(
                  yearLabel,
                  style: AppTextStyles.micro(color: AppColors.gold)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyProgress extends StatelessWidget {
  final bool complete;
  final int documentPercent;

  const _JourneyProgress({
    required this.complete,
    required this.documentPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          _ProgressItem(
            label: 'Profile',
            value: complete ? 'Ready' : 'Start',
            done: complete,
          ),
          const _ProgressDivider(),
          _ProgressItem(
            label: 'Tax scan',
            value: complete ? 'Mapped' : 'Pending',
            done: complete,
          ),
          const _ProgressDivider(),
          _ProgressItem(
            label: 'Proofs',
            value: '$documentPercent%',
            done: documentPercent >= 80,
          ),
        ],
      ),
    );
  }
}

class _ProgressItem extends StatelessWidget {
  final String label;
  final String value;
  final bool done;

  const _ProgressItem({
    required this.label,
    required this.value,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: done ? AppColors.success : AppColors.textMuted,
                size: 14,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.bodyMedium()),
        ],
      ),
    );
  }
}

class _ProgressDivider extends StatelessWidget {
  const _ProgressDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.divider,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? helper;

  const _SectionTitle({required this.title, this.helper});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTextStyles.h3())),
        if (helper != null)
          Text(
            helper!,
            style: AppTextStyles.micro(color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _NextMoveTile extends StatelessWidget {
  final NextBestAction action;
  final VoidCallback onTap;

  const _NextMoveTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.goldLight,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  shape: BoxShape.circle,
                ),
                child: Icon(action.icon, color: AppColors.gold, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title, style: AppTextStyles.bodyMedium()),
                    const SizedBox(height: 3),
                    Text(
                      action.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataImportPanel extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onDigiLocker;

  const _DataImportPanel({
    required this.onManual,
    required this.onDigiLocker,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ImportRow(
            icon: Icons.edit_note_rounded,
            title: 'Add documents manually',
            body: 'Upload or mark proofs as ready.',
            onTap: onManual,
          ),
          const Divider(height: 1, indent: 60),
          _ImportRow(
            icon: Icons.account_balance_outlined,
            title: 'Fetch from DigiLocker',
            body: 'Coming soon',
            onTap: onDigiLocker,
          ),
        ],
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _ImportRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.gold),
      title: Text(title, style: AppTextStyles.bodyMedium()),
      subtitle: Text(
        body,
        style: AppTextStyles.caption(color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _Tool {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _Tool({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
}

class _ToolList extends StatelessWidget {
  final List<_Tool> tools;

  const _ToolList({required this.tools});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: tools.asMap().entries.map((entry) {
        final tool = entry.value;
        return Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 3),
              onTap: tool.onTap,
              leading: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.bgSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(tool.icon, color: AppColors.gold, size: 19),
              ),
              title: Text(tool.title, style: AppTextStyles.bodyMedium()),
              subtitle: Text(
                tool.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
            if (entry.key != tools.length - 1)
              const Divider(height: 1, indent: 54),
          ],
        );
      }).toList(),
    );
  }
}
