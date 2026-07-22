import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/money_plan.dart';
import '../providers/money_plan_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_ui.dart';

class MoneySetupScreen extends ConsumerStatefulWidget {
  const MoneySetupScreen({super.key});

  @override
  ConsumerState<MoneySetupScreen> createState() => _MoneySetupScreenState();
}

class _MoneySetupScreenState extends ConsumerState<MoneySetupScreen> {
  final _fixed = TextEditingController();
  final _variable = TextEditingController();
  final _equity = TextEditingController();
  final _takeHome = TextEditingController();
  final _commitments = TextEditingController();
  final _investing = TextEditingController();
  final _liquid = TextEditingController();
  final _goalName = TextEditingController();
  final _goalTarget = TextEditingController();
  final _goalSaved = TextEditingController();

  int _step = 0;
  bool _hydrated = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _fixed,
      _variable,
      _equity,
      _takeHome,
      _commitments,
      _investing,
      _liquid,
      _goalName,
      _goalTarget,
      _goalSaved,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _hydrate(MoneyPlan plan) {
    if (_hydrated) return;
    _hydrated = true;
    _fixed.text = _displayAmount(plan.annualFixedPay);
    _variable.text = _displayAmount(plan.annualVariablePay);
    _equity.text = _displayAmount(plan.annualEquityPay);
    _takeHome.text = _displayAmount(plan.monthlyTakeHome);
    _commitments.text = _displayAmount(plan.monthlyCommitments);
    _investing.text = _displayAmount(plan.monthlyInvesting);
    _liquid.text = _displayAmount(plan.liquidSavings);
    _goalName.text = plan.primaryGoalName;
    _goalTarget.text = _displayAmount(plan.primaryGoalTarget);
    _goalSaved.text = _displayAmount(plan.primaryGoalSaved);
  }

  String _displayAmount(int value) => value == 0 ? '' : value.toString();

  int _amount(TextEditingController controller) =>
      int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  bool _validateStep() {
    final valid = switch (_step) {
      0 => _amount(_fixed) > 0,
      1 => _amount(_takeHome) > 0,
      2 => _amount(_commitments) + _amount(_investing) <= _amount(_takeHome),
      _ => true,
    };
    setState(() {
      _error = valid
          ? null
          : _step == 2
              ? 'Commitments and investing cannot exceed take-home.'
              : 'Add a value to continue.';
    });
    return valid;
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    if (!_validateStep()) return;
    HapticFeedback.lightImpact();
    if (_step < 3) {
      setState(() => _step += 1);
      return;
    }

    setState(() => _saving = true);
    final plan = MoneyPlan(
      annualFixedPay: _amount(_fixed),
      annualVariablePay: _amount(_variable),
      annualEquityPay: _amount(_equity),
      monthlyTakeHome: _amount(_takeHome),
      monthlyCommitments: _amount(_commitments),
      monthlyInvesting: _amount(_investing),
      liquidSavings: _amount(_liquid),
      primaryGoalName: _goalName.text.trim(),
      primaryGoalTarget: _amount(_goalTarget),
      primaryGoalSaved: _amount(_goalSaved),
    );
    await ref.read(moneyPlanProvider.notifier).save(plan);
    if (!mounted) return;
    context.go('/discover');
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(moneyPlanProvider);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step -= 1);
      },
      child: ArthScaffold(
        showAmbientGlow: false,
        child: planAsync.when(
          loading: () => const ArthLoadingPanel(
            title: 'Opening your money plan',
            insights: ['Loading your saved baseline.'],
          ),
          error: (_, __) => ArthStatePanel(
            icon: Icons.sync_problem_rounded,
            title: 'Could not open the plan',
            message: 'Retry before entering financial information.',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(moneyPlanProvider),
          ),
          data: (plan) {
            _hydrate(plan);
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _step == 0 ? 'Close setup' : 'Previous step',
                          onPressed: () {
                            if (_step == 0) {
                              context.go('/discover');
                            } else {
                              setState(() => _step -= 1);
                            }
                          },
                          icon: Icon(
                            _step == 0
                                ? Icons.close_rounded
                                : Icons.arrow_back_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (_step + 1) / 4,
                            minHeight: 3,
                            backgroundColor: AppColors.surfaceMuted,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text('${_step + 1} of 4', style: AppTextStyles.micro()),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      child: SingleChildScrollView(
                        key: ValueKey(_step),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MoneyFlowGraphic(step: _step),
                            const SizedBox(height: 28),
                            Text(
                              _titleForStep(_step),
                              style: AppTextStyles.h1().copyWith(
                                fontSize: 36,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _helperForStep(_step),
                              style: AppTextStyles.body(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _fieldsForStep(_step),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: AppTextStyles.caption(
                                  color: AppColors.alert,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: AppButtons.primaryGold,
                        onPressed: _saving ? null : _continue,
                        child: Text(_step == 3 ? 'Build my plan' : 'Continue'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _titleForStep(int step) => switch (step) {
        0 => 'How are you paid?',
        1 => 'What actually reaches you?',
        2 => 'What is already spoken for?',
        _ => 'What are you building toward?',
      };

  String _helperForStep(int step) => switch (step) {
        0 =>
          'Use annual amounts. Keep equity at zero if it is not part of your compensation.',
        1 =>
          'Use the average amount credited after tax and payroll deductions.',
        2 =>
          'Commitments include rent, EMIs, bills and family support. Keep lifestyle spending out for now.',
        _ =>
          'Liquid savings means money you can access quickly. A goal is optional.',
      };

  Widget _fieldsForStep(int step) => switch (step) {
        0 => Column(
            children: [
              _MoneyField(controller: _fixed, label: 'Annual fixed pay'),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _variable,
                label: 'Annual variable pay',
                optional: true,
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _equity,
                label: 'Annual equity value',
                optional: true,
              ),
            ],
          ),
        1 => _MoneyField(
            controller: _takeHome,
            label: 'Average monthly take-home',
          ),
        2 => Column(
            children: [
              _MoneyField(
                controller: _commitments,
                label: 'Monthly fixed commitments',
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _investing,
                label: 'Monthly investing or saving',
                optional: true,
              ),
            ],
          ),
        _ => Column(
            children: [
              _MoneyField(
                controller: _liquid,
                label: 'Current liquid savings',
                optional: true,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _goalName,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Primary goal (optional)',
                  hintText: 'Home deposit, travel, career break',
                ),
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _goalTarget,
                label: 'Goal target',
                optional: true,
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _goalSaved,
                label: 'Already saved for goal',
                optional: true,
              ),
            ],
          ),
      };
}

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool optional;

  const _MoneyField({
    required this.controller,
    required this.label,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        hintText: '0',
        helperText: optional ? 'Optional' : null,
      ),
    );
  }
}

class _MoneyFlowGraphic extends StatelessWidget {
  final int step;

  const _MoneyFlowGraphic({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Income', 'Take-home', 'Committed', 'Purpose'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index <= step;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.medium,
                      height: 48 + (index == step ? 14 : 0),
                      decoration: BoxDecoration(
                        color: active ? AppColors.ink : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.micro(
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < labels.length - 1) const SizedBox(width: 7),
            ],
          ),
        );
      }),
    );
  }
}
