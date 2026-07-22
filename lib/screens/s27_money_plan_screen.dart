import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/money_plan.dart';
import '../providers/money_plan_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class MoneyPlanScreen extends ConsumerWidget {
  const MoneyPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(moneyPlanProvider);
    return ArthScaffold(
      showAmbientGlow: false,
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (index) => goToArthTab(context, index),
      ),
      child: planAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Opening your plan',
          insights: ['Preparing monthly allocation and runway.'],
        ),
        error: (_, __) => ArthStatePanel(
          icon: Icons.sync_problem_rounded,
          title: 'Plan unavailable',
          message: 'Your saved values could not be read.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(moneyPlanProvider),
        ),
        data: (plan) =>
            plan.isComplete ? _PlanBody(plan: plan) : const _PlanEmptyState(),
      ),
    );
  }
}

class _PlanEmptyState extends StatelessWidget {
  const _PlanEmptyState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan', style: AppTextStyles.h2()),
            const Spacer(),
            Text(
              'A plan needs a baseline.',
              style: AppTextStyles.h1().copyWith(fontSize: 40),
            ),
            const SizedBox(height: 14),
            Text(
              'Add real take-home, commitments and savings before ARTH calculates what remains available.',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: () => context.push('/money-setup'),
                child: const Text('Build baseline'),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  final MoneyPlan plan;

  const _PlanBody({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = MoneySnapshot(plan);
    final taxComplete =
        ref.watch(completedTaxProfileProvider).asData?.value ?? false;
    final decision = nextMoneyDecision(
      plan,
      taxProfileComplete: taxComplete,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Plan', style: AppTextStyles.h2()),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit baseline',
                  onPressed: () => context.push('/money-setup'),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              'FREE TO ASSIGN THIS MONTH',
              style: AppTextStyles.sectionLabel(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatRupeesCompact(snapshot.availableThisMonth),
              style: AppTextStyles.display(color: AppColors.ink).copyWith(
                fontSize: 54,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'After fixed commitments and your current monthly investing amount.',
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 30),
            _AllocationBar(plan: plan, snapshot: snapshot),
            const SizedBox(height: 28),
            _DecisionPanel(
              decision: decision,
              onTap: () => context.push(decision.route),
            ),
            const SizedBox(height: 34),
            Text('Resilience', style: AppTextStyles.h2()),
            const SizedBox(height: 12),
            _MetricLine(
              label: 'Liquid runway',
              value:
                  '${snapshot.emergencyRunwayMonths.toStringAsFixed(1)} months',
              helper: 'Based on fixed commitments only',
            ),
            if (plan.primaryGoalTarget > 0) ...[
              const Divider(height: 28),
              _MetricLine(
                label: plan.primaryGoalName.isEmpty
                    ? 'Primary goal'
                    : plan.primaryGoalName,
                value: '${(snapshot.goalProgress * 100).round()}%',
                helper:
                    '${formatRupeesCompact(plan.primaryGoalSaved)} of ${formatRupeesCompact(plan.primaryGoalTarget)}',
              ),
            ],
            const SizedBox(height: 34),
            Text('Explore a decision', style: AppTextStyles.h2()),
            const SizedBox(height: 12),
            _PlanTool(
              icon: Icons.shopping_bag_outlined,
              title: 'Test a one-time purchase',
              body: 'See how a purchase changes your liquid runway.',
              onTap: () => _showPurchaseScenario(context, plan),
            ),
            _PlanTool(
              icon: Icons.calculate_outlined,
              title: 'Tax plan',
              body: 'Compare regimes and review possible deductions.',
              onTap: () => context.push(
                taxComplete ? '/action-plan' : '/questions',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPurchaseScenario(BuildContext context, MoneyPlan plan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PurchaseScenario(plan: plan),
    );
  }
}

class _AllocationBar extends StatelessWidget {
  final MoneyPlan plan;
  final MoneySnapshot snapshot;

  const _AllocationBar({required this.plan, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final income = plan.monthlyTakeHome;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                if (plan.monthlyCommitments > 0)
                  Expanded(
                    flex: plan.monthlyCommitments,
                    child: Container(color: AppColors.ink),
                  ),
                if (plan.monthlyInvesting > 0)
                  Expanded(
                    flex: plan.monthlyInvesting,
                    child: Container(color: AppColors.warning),
                  ),
                if (snapshot.availableThisMonth > 0)
                  Expanded(
                    flex: snapshot.availableThisMonth,
                    child: Container(color: AppColors.primary),
                  ),
                if (income == 0) Expanded(child: Container()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend(
              color: AppColors.ink,
              label:
                  'Committed ${formatRupeesCompact(plan.monthlyCommitments)}',
            ),
            _Legend(
              color: AppColors.warning,
              label: 'Investing ${formatRupeesCompact(plan.monthlyInvesting)}',
            ),
            _Legend(
              color: AppColors.primary,
              label: 'Free ${formatRupeesCompact(snapshot.availableThisMonth)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.micro()),
      ],
    );
  }
}

class _DecisionPanel extends StatelessWidget {
  final MoneyDecision decision;
  final VoidCallback onTap;

  const _DecisionPanel({required this.decision, required this.onTap});

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEXT DECISION',
                style: AppTextStyles.sectionLabel(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              Text(decision.title,
                  style: AppTextStyles.h2(color: Colors.white)),
              const SizedBox(height: 7),
              Text(
                decision.body,
                style: AppTextStyles.caption(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      decision.actionLabel,
                      style: AppTextStyles.button(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;
  final String helper;

  const _MetricLine({
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyMedium()),
              const SizedBox(height: 3),
              Text(helper, style: AppTextStyles.micro()),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.right,
            style: AppTextStyles.h3(),
          ),
        ),
      ],
    );
  }
}

class _PlanTool extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _PlanTool({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: AppTextStyles.bodyMedium()),
      subtitle: Text(body, style: AppTextStyles.caption()),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _PurchaseScenario extends StatefulWidget {
  final MoneyPlan plan;

  const _PurchaseScenario({required this.plan});

  @override
  State<_PurchaseScenario> createState() => _PurchaseScenarioState();
}

class _PurchaseScenarioState extends State<_PurchaseScenario> {
  double _purchase = 100000;

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.plan.liquidSavings - _purchase).clamp(0, 1e12);
    final runway = widget.plan.monthlyCommitments == 0
        ? 0.0
        : remaining / widget.plan.monthlyCommitments;
    final max = widget.plan.liquidSavings > 100000
        ? widget.plan.liquidSavings.toDouble()
        : 100000.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test a purchase', style: AppTextStyles.h2()),
            const SizedBox(height: 8),
            Text(
              'This does not judge the purchase. It shows the effect on liquid savings.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 26),
            Text(
              formatRupeesCompact(_purchase.round()),
              style: AppTextStyles.displaySmall(color: AppColors.ink),
            ),
            Slider(
              value: _purchase.clamp(0, max),
              min: 0,
              max: max,
              divisions: 20,
              onChanged: (value) => setState(() => _purchase = value),
            ),
            const SizedBox(height: 12),
            _MetricLine(
              label: 'Savings left',
              value: formatRupeesCompact(remaining.round()),
              helper:
                  '${runway.toStringAsFixed(1)} months of fixed commitments',
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
