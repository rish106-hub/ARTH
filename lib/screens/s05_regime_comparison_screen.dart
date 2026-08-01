import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../models/tax_rule_set.dart';
import '../models/tax_result.dart';
import '../providers/tax_result_provider.dart';
import '../widgets/animated_number.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';
import '../widgets/tax_rule_badge.dart';

class RegimeComparisonScreen extends ConsumerWidget {
  const RegimeComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(taxResultProvider);

    return Scaffold(
      backgroundColor: PaycheckColors.bgPrimary,
      appBar: const ArthAppBar(title: 'Old vs New Regime'),
      body: resultAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Comparing regimes',
          insights: [
            'Checking old and new regime outcomes.',
            'Keeping assumptions conservative.',
            'Finding the cleaner tax route.',
          ],
        ),
        error: (_, __) => RetryErrorState(
          message: 'Could not load your regime comparison',
          onRetry: () => ref.invalidate(taxResultProvider),
        ),
        data: (result) => _RegimeContent(result: result),
      ),
    );
  }
}

class _RegimeContent extends StatelessWidget {
  final TaxResult result;
  const _RegimeContent({required this.result});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedCards = constraints.maxWidth < 380;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TaxYearSelector(),
              const SizedBox(height: 16),
              TaxRuleBadge(result: result),
              const SizedBox(height: 16),
              Text(
                'Based on your profile:',
                style:
                    PaycheckType.caption(color: PaycheckColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                '${result.betterRegimeLabel} saves you more money.',
                style: PaycheckType.h2(color: PaycheckColors.gold),
              ),
              const SizedBox(height: 24),
              (useStackedCards
                      ? Column(
                          children: [
                            _RegimeCard(
                              title: 'Old Regime',
                              tax: result.oldRegimeTax,
                              taxableIncome: result.oldRegimeTaxableIncome,
                              deductions: result.totalDeductionsOld,
                              isBetter: result.isOldBetter,
                              savings: result.isOldBetter
                                  ? result.regimeSavings
                                  : null,
                              isNew: false,
                            ),
                            const SizedBox(height: 12),
                            _RegimeCard(
                              title: 'New Regime',
                              tax: result.newRegimeTax,
                              taxableIncome: result.newRegimeTaxableIncome,
                              deductions: 75000,
                              isBetter: !result.isOldBetter,
                              savings: !result.isOldBetter
                                  ? result.regimeSavings
                                  : null,
                              isNew: true,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _RegimeCard(
                                title: 'Old Regime',
                                tax: result.oldRegimeTax,
                                taxableIncome: result.oldRegimeTaxableIncome,
                                deductions: result.totalDeductionsOld,
                                isBetter: result.isOldBetter,
                                savings: result.isOldBetter
                                    ? result.regimeSavings
                                    : null,
                                isNew: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RegimeCard(
                                title: 'New Regime',
                                tax: result.newRegimeTax,
                                taxableIncome: result.newRegimeTaxableIncome,
                                deductions: 75000,
                                isBetter: !result.isOldBetter,
                                savings: !result.isOldBetter
                                    ? result.regimeSavings
                                    : null,
                                isNew: true,
                              ),
                            ),
                          ],
                        ))
                  .animate()
                  .slideX(begin: 0.1, duration: 400.ms, curve: Curves.easeOut)
                  .fadeIn(duration: 400.ms),
              const SizedBox(height: 24),
              if (result.regimeSavings > 0)
                _SavingsCallout(
                  betterRegime: result.betterRegimeLabel,
                  savings: result.regimeSavings,
                  isOldBetter: result.isOldBetter,
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PaycheckColors.bgCard,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: PaycheckColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: PaycheckColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Uses your entered amounts plus modeled rent/HRA.',
                        style: PaycheckType.micro(
                          color: PaycheckColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (result.assumptions.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AssumptionsPanel(assumptions: result.assumptions),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    style: AppButtons.outlineGold,
                    onPressed: () => context.push('/accuracy-coach'),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Improve accuracy'),
                  ),
                  OutlinedButton.icon(
                    style: AppButtons.outlineGold,
                    onPressed: () => context.push('/tax-simulator'),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('What-if'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('General Guidance by Income', style: PaycheckType.h3()),
              const SizedBox(height: 12),
              const _IncomeGuidance(),
              const SizedBox(height: 24),
              Text('Old Regime Deduction Stack', style: PaycheckType.h3()),
              const SizedBox(height: 12),
              _DeductionBreakdown(result: result),
            ],
          );
        },
      ),
    );
  }
}

class _AssumptionsPanel extends StatelessWidget {
  final List<TaxAssumption> assumptions;

  const _AssumptionsPanel({required this.assumptions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.amber.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calculation assumptions', style: PaycheckType.h3()),
          const SizedBox(height: 8),
          ...assumptions.take(4).map(
            (item) {
              final caution = item.severity == TaxAssumptionSeverity.caution;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: caution
                      ? PaycheckColors.amber.withValues(alpha: 0.10)
                      : PaycheckColors.bgSurface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: caution
                        ? PaycheckColors.amber.withValues(alpha: 0.32)
                        : PaycheckColors.border,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      caution
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded,
                      size: 15,
                      color: caution
                          ? PaycheckColors.amber
                          : PaycheckColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.title}: ${item.detail}',
                        style: PaycheckType.micro(
                          color: caution
                              ? PaycheckColors.textPrimary
                              : PaycheckColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (assumptions.length > 4)
            Text(
              '+${assumptions.length - 4} more assumption${assumptions.length - 4 == 1 ? '' : 's'} affect this estimate.',
              style: PaycheckType.micro(color: PaycheckColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _RegimeCard extends StatelessWidget {
  final String title;
  final double tax;
  final double taxableIncome;
  final double deductions;
  final bool isBetter;
  final double? savings;
  final bool isNew;

  const _RegimeCard({
    required this.title,
    required this.tax,
    required this.taxableIncome,
    required this.deductions,
    required this.isBetter,
    this.savings,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: isBetter ? PaycheckColors.gold : PaycheckColors.border,
          width: isBetter ? 1.5 : 1,
        ),
        boxShadow: isBetter
            ? [
                BoxShadow(
                  color: PaycheckColors.gold.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isBetter
                  ? PaycheckColors.gold.withValues(alpha: 0.1)
                  : PaycheckColors.bgSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                Text(
                  title,
                  style: PaycheckType.caption(
                    color: isBetter
                        ? PaycheckColors.gold
                        : PaycheckColors.textSecondary,
                  ),
                ),
                if (isBetter) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Better for you',
                    style: PaycheckType.micro(color: PaycheckColors.gold),
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Tax payable',
                  style:
                      PaycheckType.micro(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 4),
                AnimatedRupeeNumber(
                  value: tax.round(),
                  style: PaycheckType.h2(
                    color: isBetter
                        ? PaycheckColors.success
                        : PaycheckColors.textPrimary,
                  ),
                  duration: const Duration(milliseconds: 1200),
                ),
                const SizedBox(height: 12),
                _InfoRow(label: 'Taxable income', value: taxableIncome.round()),
                const SizedBox(height: 8),
                _InfoRow(
                  label: isNew ? 'Std deduction' : 'Deductions',
                  value: deductions.round(),
                ),
                if (savings != null && savings! > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: PaycheckColors.success.withValues(alpha: 0.1),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Save more by',
                          style: PaycheckType.micro(
                            color: PaycheckColors.textSecondary,
                          ),
                        ),
                        RupeeText(
                          amount: savings!.round(),
                          style: PaycheckType.h3(color: PaycheckColors.success),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final int value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: PaycheckType.micro(), softWrap: true),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            formatRupeesCompact(value),
            style: PaycheckType.micro(color: PaycheckColors.textPrimary),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SavingsCallout extends StatelessWidget {
  final String betterRegime;
  final double savings;
  final bool isOldBetter;

  const _SavingsCallout({
    required this.betterRegime,
    required this.savings,
    required this.isOldBetter,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PaycheckColors.gold.withValues(alpha: 0.1),
            PaycheckColors.gold.withValues(alpha: 0.03),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: PaycheckColors.gold,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$betterRegime saves you',
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
                Text(
                  formatRupeesCompact(savings.round()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (isCompact
                          ? PaycheckType.h3(color: PaycheckColors.gold)
                          : PaycheckType.h2(color: PaycheckColors.gold))
                      .copyWith(height: 1.1),
                ),
                Text(
                  'more every year.',
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

class _DeductionBreakdown extends StatelessWidget {
  final TaxResult result;
  const _DeductionBreakdown({required this.result});

  @override
  Widget build(BuildContext context) {
    // Build list of triggered deductions
    final items = result.gaps
        .map(
          (g) => _DeductionRow(
            section: g.section,
            label: g.title,
            amount: g.gapAmount,
          ),
        )
        .toList();

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: PaycheckColors.bgCard,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          'No gaps found in old regime deductions.',
          style: PaycheckType.caption(color: PaycheckColors.textSecondary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.border),
      ),
      child: Column(
        children: items
            .map(
              (item) => Column(
                children: [
                  item,
                  const Divider(height: 1, color: PaycheckColors.divider),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DeductionRow extends StatelessWidget {
  final String section;
  final String label;
  final int amount;

  const _DeductionRow({
    required this.section,
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: PaycheckColors.gold.withValues(alpha: 0.1),
              borderRadius: AppRadius.pill,
            ),
            child: Text(section, style: PaycheckType.sectionLabel()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: PaycheckType.caption(), softWrap: true),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              formatRupeesCompact(amount),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: PaycheckType.caption(color: PaycheckColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeGuidance extends StatelessWidget {
  const _IncomeGuidance();

  static const _items = [
    _GuidanceItem(
      range: 'Up to ₹12.75L salary',
      rec: 'New Regime',
      reason: 'Rebate plus standard deduction can make tax zero',
      color: PaycheckColors.success,
    ),
    _GuidanceItem(
      range: '₹12.75L – ₹24L',
      rec: 'Usually New',
      reason: 'Lower slabs help unless old-regime deductions are strong',
      color: PaycheckColors.success,
    ),
    _GuidanceItem(
      range: '₹24L – ₹50L',
      rec: 'Compare both',
      reason: 'Old can win with HRA, 80C, NPS, insurance, or home loan',
      color: PaycheckColors.gold,
    ),
    _GuidanceItem(
      range: 'Above ₹50L',
      rec: 'Consult CA',
      reason: 'Surcharge impact matters',
      color: PaycheckColors.textSecondary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.border),
      ),
      child: Column(
        children: _items.map((item) => _GuidanceRow(item: item)).toList(),
      ),
    );
  }
}

class _GuidanceItem {
  final String range;
  final String rec;
  final String reason;
  final Color color;
  const _GuidanceItem({
    required this.range,
    required this.rec,
    required this.reason,
    required this.color,
  });
}

class _GuidanceRow extends StatelessWidget {
  final _GuidanceItem item;
  const _GuidanceRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PaycheckColors.divider)),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.range, style: PaycheckType.caption()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.1),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        item.rec,
                        style: PaycheckType.micro(color: item.color),
                      ),
                    ),
                    Text(item.reason, style: PaycheckType.micro()),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(item.range, style: PaycheckType.caption()),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    item.rec,
                    style: PaycheckType.micro(color: item.color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.reason,
                    style: PaycheckType.micro(),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
    );
  }
}
