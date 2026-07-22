import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/money_plan.dart';
import '../providers/money_plan_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class IncomeScreen extends ConsumerWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(moneyPlanProvider);
    return ArthScaffold(
      showAmbientGlow: false,
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 1,
        onTap: (index) => goToArthTab(context, index),
      ),
      child: planAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Reading your income map',
          insights: ['Loading compensation and take-home.'],
        ),
        error: (_, __) => ArthStatePanel(
          icon: Icons.sync_problem_rounded,
          title: 'Income map unavailable',
          message: 'Your saved values could not be read.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(moneyPlanProvider),
        ),
        data: (plan) => plan.isComplete
            ? _IncomeBody(plan: plan)
            : const _IncomeEmptyState(),
      ),
    );
  }
}

class _IncomeEmptyState extends StatelessWidget {
  const _IncomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Income', style: AppTextStyles.h2()),
            const Spacer(),
            Text(
              'Map how money reaches you.',
              style: AppTextStyles.h1().copyWith(fontSize: 40),
            ),
            const SizedBox(height: 14),
            Text(
              'Separate fixed pay, variable income, equity and actual take-home before making a plan.',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: () => context.push('/money-setup'),
                child: const Text('Add my income'),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _IncomeBody extends ConsumerWidget {
  final MoneyPlan plan;

  const _IncomeBody({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxComplete =
        ref.watch(completedTaxProfileProvider).asData?.value ?? false;
    final taxResult =
        taxComplete ? ref.watch(taxResultProvider).asData?.value : null;
    final total = plan.totalCompensation;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Income', style: AppTextStyles.h2()),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit income',
                  onPressed: () => context.push('/money-setup'),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text(
              'EXPECTED ANNUAL COMPENSATION',
              style: AppTextStyles.sectionLabel(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              formatRupeesCompact(total),
              style: AppTextStyles.display(color: AppColors.ink).copyWith(
                fontSize: 52,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatRupeesCompact(plan.monthlyTakeHome)} reaches you in an average month.',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 30),
            _CompositionBar(plan: plan),
            const SizedBox(height: 22),
            _IncomeRow(
              color: AppColors.ink,
              label: 'Fixed pay',
              value: plan.annualFixedPay,
            ),
            if (plan.annualVariablePay > 0)
              _IncomeRow(
                color: AppColors.warning,
                label: 'Variable pay',
                value: plan.annualVariablePay,
              ),
            if (plan.annualEquityPay > 0)
              _IncomeRow(
                color: AppColors.primary,
                label: 'Equity compensation',
                value: plan.annualEquityPay,
              ),
            const SizedBox(height: 34),
            Text('Tax layer', style: AppTextStyles.h2()),
            const SizedBox(height: 10),
            if (taxResult == null)
              _TaxLayerPrompt(
                onTap: () => context.push('/questions'),
              )
            else
              _TaxLayerResult(
                annualTax: taxResult.currentTax.round(),
                regime: taxResult.betterRegimeLabel,
                confidence: taxResult.confidenceLabel,
                onTap: () => context.push('/regime-comparison'),
              ),
            const SizedBox(height: 28),
            _UtilityRow(
              icon: Icons.folder_outlined,
              title: 'Income and tax documents',
              body: 'Form 16, AIS and supporting proof.',
              onTap: () => context.push('/documents'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompositionBar extends StatelessWidget {
  final MoneyPlan plan;

  const _CompositionBar({required this.plan});

  @override
  Widget build(BuildContext context) {
    final total = plan.totalCompensation;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 16,
        child: Row(
          children: [
            Expanded(
              flex: plan.annualFixedPay,
              child: Container(color: AppColors.ink),
            ),
            if (plan.annualVariablePay > 0)
              Expanded(
                flex: plan.annualVariablePay,
                child: Container(color: AppColors.warning),
              ),
            if (plan.annualEquityPay > 0)
              Expanded(
                flex: plan.annualEquityPay,
                child: Container(color: AppColors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _IncomeRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTextStyles.body())),
          Text(formatRupeesCompact(value), style: AppTextStyles.bodyMedium()),
        ],
      ),
    );
  }
}

class _TaxLayerPrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _TaxLayerPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _UtilityRow(
      icon: Icons.calculate_outlined,
      title: 'Tax position not mapped',
      body: 'Run the tax check to compare regimes and improve the annual view.',
      onTap: onTap,
    );
  }
}

class _TaxLayerResult extends StatelessWidget {
  final int annualTax;
  final String regime;
  final String confidence;
  final VoidCallback onTap;

  const _TaxLayerResult({
    required this.annualTax,
    required this.regime,
    required this.confidence,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated annual tax',
                      style: AppTextStyles.caption(color: Colors.white60),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatRupeesCompact(annualTax),
                      style: AppTextStyles.h2(color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$regime · $confidence',
                      style: AppTextStyles.micro(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _UtilityRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyMedium()),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: AppTextStyles.caption(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
