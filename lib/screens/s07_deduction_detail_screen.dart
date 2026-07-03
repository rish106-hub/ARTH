import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/gap_card.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../engine/tax_engine.dart';
import '../widgets/animated_number.dart';
import '../widgets/question_progress_bar.dart';

class DeductionDetailScreen extends ConsumerWidget {
  final GapCard gap;
  const DeductionDetailScreen({super.key, required this.gap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone = ref.watch(gapStateProvider)[gap.id] ?? false;
    final profile = ref.watch(userProfileProvider);
    final taxSaved = (gap.gapAmount *
            TaxEngine.marginalRateOldRegime(profile.annualCTC.toDouble()) *
            1.04)
        .round();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: ArthAppBar(title: gap.section),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            _HeroBanner(gap: gap, isDone: isDone),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section code + title
                  Text(gap.title, style: AppTextStyles.h2()),
                  const SizedBox(height: 4),
                  Text(
                    gap.shortDesc,
                    style: AppTextStyles.caption(
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Plain English explanation
                  Text('What is this?', style: AppTextStyles.h3()),
                  const SizedBox(height: 8),
                  Text(gap.message, style: AppTextStyles.body()),

                  const SizedBox(height: 20),

                  // Gap + tax saved cards
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'You\'re leaving behind',
                          value: gap.gapAmount,
                          color: gap.accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Tax saved if you act',
                          value: taxSaved,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Details
                  _DetailSection(gap: gap),

                  const SizedBox(height: 20),

                  // Actions
                  Text('Take Action', style: AppTextStyles.h3()),
                  const SizedBox(height: 12),
                  ...gap.actions.map(
                    (action) => _ActionButton(
                      action: action,
                      accentColor: gap.accentColor,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Mark done button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDone
                            ? AppColors.bgSurface
                            : AppColors.success.withValues(alpha: 0.15),
                        foregroundColor: isDone
                            ? AppColors.textSecondary
                            : AppColors.success,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: isDone
                              ? AppColors.border
                              : AppColors.success.withValues(alpha: 0.5),
                        ),
                      ),
                      onPressed: () {
                        ref.read(gapStateProvider.notifier).toggle(gap.id);
                        if (!isDone) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Marked done. Gap recalculated.',
                                style: AppTextStyles.caption(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              backgroundColor: AppColors.bgCard,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        isDone
                            ? Icons.undo_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(isDone ? 'Mark as Not Done' : 'Mark Done'),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Legal footer
                  Center(
                    child: Text(
                      'Powered by Income Tax Act 1961 + Finance Act 2026',
                      style: AppTextStyles.micro(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final GapCard gap;
  final bool isDone;

  const _HeroBanner({required this.gap, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          bottom: BorderSide(color: gap.accentColor.withValues(alpha: 0.3)),
          top: BorderSide(color: gap.accentColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: gap.accentColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.pill,
                    border: Border.all(
                      color: gap.accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    gap.section,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sectionLabel(color: gap.accentColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      gap.difficultyIcon,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        gap.difficultyLabel,
                        softWrap: true,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.micro(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isDone ? 'You claimed this gap!' : 'You\'re leaving behind',
            style: AppTextStyles.caption(
              color: isDone ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedRupeeNumber(
            value: gap.gapAmount,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: isDone ? AppColors.success : gap.accentColor,
              height: 1,
            ),
            duration: const Duration(milliseconds: 1200),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 12,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Deadline: ${gap.deadline}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.card,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.micro()),
          const SizedBox(height: 4),
          RupeeText(
            amount: value,
            style: AppTextStyles.h3(color: color),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final GapCard gap;
  const _DetailSection({required this.gap});

  @override
  Widget build(BuildContext context) {
    final details = _getDetails(gap.id);
    if (details.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Key Points', style: AppTextStyles.h3()),
        const SizedBox(height: 10),
        ...details.map(
          (d) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: AppTextStyles.body(color: AppColors.gold)),
                Expanded(child: Text(d, style: AppTextStyles.body())),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<String> _getDetails(String id) {
    switch (id) {
      case 'T01_80C_gap':
        return [
          'Includes: ELSS, PPF, EPF, LIC, NSC, Tax-Saving FD, Tuition Fees',
          'EPF contributions (yours + employer) auto-count',
          'Lock-in: 3 years for ELSS, 15 years for PPF',
          'Max deduction: ₹1,50,000',
        ];
      case 'T02_80CCD1B_nps':
        return [
          'This is EXTRA deduction — over and above ₹1.5L 80C limit',
          'Total possible: ₹2,00,000 (80C + 80CCD1B)',
          'Open NPS Tier-1 account on NSDL in 30 minutes',
          'Only available in old regime',
        ];
      case 'T03_80D_self':
        return [
          'Covers self, spouse, and children on one policy',
          'Includes annual premium + preventive checkup (up to ₹5,000)',
          'Payment must be non-cash (except preventive checkup)',
          'Limit: ₹25,000 if below 60, ₹50,000 if 60+',
        ];
      case 'T07_80E_education_loan':
        return [
          'NO upper limit on interest deduction',
          'Available for 8 years starting from year of first repayment',
          'Covers: higher education (grad/post-grad) in India or abroad',
          'Loan must be from recognized bank / NBFC, not family',
        ];
      case 'T08_section24b_home_loan':
        return [
          'Deduct home loan interest up to ₹2,00,000 for self-occupied property',
          'No cap for let-out properties (available in both regimes)',
          'Construction must complete within 5 years of loan',
          'Get interest certificate from your bank',
        ];
      default:
        return [];
    }
  }
}

class _ActionButton extends StatelessWidget {
  final GapAction action;
  final Color accentColor;

  const _ActionButton({required this.action, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor.withValues(alpha: 0.12),
            foregroundColor: accentColor,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
          ),
          onPressed: () async {
            final uri = Uri.parse('https://arth-website.vercel.app/');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(action.label),
        ),
      ),
    );
  }
}
