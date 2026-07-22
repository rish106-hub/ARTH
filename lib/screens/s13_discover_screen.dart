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

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(moneyPlanProvider);
    return ArthScaffold(
      showAmbientGlow: false,
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 0,
        onTap: (index) => goToArthTab(context, index),
      ),
      child: planAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Opening Today',
          insights: ['Reading your money baseline.'],
        ),
        error: (_, __) => ArthStatePanel(
          icon: Icons.sync_problem_rounded,
          title: 'Today is unavailable',
          message: 'Your saved money plan could not be read.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(moneyPlanProvider),
        ),
        data: (plan) => _TodayView(plan: plan),
      ),
    );
  }
}

class _TodayView extends ConsumerWidget {
  final MoneyPlan plan;

  const _TodayView({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final taxComplete =
        ref.watch(completedTaxProfileProvider).asData?.value ?? false;
    final decision = nextMoneyDecision(
      plan,
      taxProfileComplete: taxComplete,
    );
    final snapshot = MoneySnapshot(plan);
    final firstName = profile.name.trim().split(' ').firstOrNull;

    final headline = plan.isComplete
        ? '${formatRupeesCompact(snapshot.availableThisMonth)} is still unassigned this month.'
        : 'Your money has no working plan yet.';
    final contextLine = plan.isComplete
        ? 'After ${formatRupeesCompact(plan.monthlyCommitments)} in fixed commitments and ${formatRupeesCompact(plan.monthlyInvesting)} in planned investing.'
        : 'Start with what reaches your bank, what is already committed, and what you have in reserve.';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).vertical -
                112,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TodayHeader(
                name: firstName,
                onProfile: () => context.go('/profile'),
              ),
              const SizedBox(height: 54),
              Text('TODAY', style: AppTextStyles.sectionLabel()),
              const SizedBox(height: 12),
              Text(
                headline,
                style: AppTextStyles.h1().copyWith(fontSize: 40, height: 1.05),
              ),
              const SizedBox(height: 16),
              Text(
                contextLine,
                style: AppTextStyles.body(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 36),
              _DecisionCard(
                decision: decision,
                onTap: () => context.push(decision.route),
              ),
              const SizedBox(height: 42),
              if (plan.isComplete)
                _MonthFlow(plan: plan, snapshot: snapshot)
              else
                const _BaselinePreview(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  final String? name;
  final VoidCallback onProfile;

  const _TodayHeader({required this.name, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final validName = name != null && name!.trim().isNotEmpty;
    return Row(
      children: [
        Text('ARTH', style: AppTextStyles.h3()),
        const Spacer(),
        IconButton(
          tooltip: 'Account and privacy',
          onPressed: onProfile,
          icon: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.ink,
            child: Text(
              validName ? name!.substring(0, 1).toUpperCase() : 'A',
              style: AppTextStyles.caption(color: AppColors.surface),
            ),
          ),
        ),
      ],
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final MoneyDecision decision;
  final VoidCallback onTap;

  const _DecisionCard({required this.decision, required this.onTap});

  IconData get _icon => switch (decision.kind) {
        MoneyDecisionKind.setup => Icons.tune_rounded,
        MoneyDecisionKind.cashBuffer => Icons.shield_outlined,
        MoneyDecisionKind.commitments => Icons.balance_outlined,
        MoneyDecisionKind.goal => Icons.flag_outlined,
        MoneyDecisionKind.taxCheck => Icons.calculate_outlined,
        MoneyDecisionKind.review => Icons.task_alt_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      decision.title,
                      style: AppTextStyles.h3(color: Colors.white),
                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthFlow extends StatelessWidget {
  final MoneyPlan plan;
  final MoneySnapshot snapshot;

  const _MonthFlow({required this.plan, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'THIS MONTH',
              style: AppTextStyles.sectionLabel(
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              formatRupeesCompact(plan.monthlyTakeHome),
              style: AppTextStyles.caption(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 12,
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('COMMITTED', style: AppTextStyles.micro()),
            Text(
              'INVESTING',
              style: AppTextStyles.micro(color: AppColors.warning),
            ),
            Text(
              'FREE',
              style: AppTextStyles.micro(color: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }
}

class _BaselinePreview extends StatelessWidget {
  const _BaselinePreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR FIRST BASELINE',
          style: AppTextStyles.sectionLabel(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        const _PreviewRow(label: 'What reaches you', icon: Icons.south_rounded),
        const _PreviewRow(
          label: 'What is already committed',
          icon: Icons.lock_outline_rounded,
        ),
        const _PreviewRow(
          label: 'What remains available',
          icon: Icons.call_split_rounded,
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PreviewRow({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTextStyles.body())),
        ],
      ),
    );
  }
}

extension _FirstOrNull on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
