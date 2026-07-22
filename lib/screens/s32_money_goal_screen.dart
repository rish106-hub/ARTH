import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/money_goal.dart';
import '../providers/money_goal_provider.dart';
import '../providers/paycheck_provider.dart';
import '../theme/paycheck_theme.dart';

class MoneyGoalScreen extends ConsumerStatefulWidget {
  const MoneyGoalScreen({super.key});

  @override
  ConsumerState<MoneyGoalScreen> createState() => _MoneyGoalScreenState();
}

class _MoneyGoalScreenState extends ConsumerState<MoneyGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _current = TextEditingController();
  final _essentials = TextEditingController();
  final _family = TextEditingController();
  String _category = 'safety';
  DateTime _targetDate = DateTime.now().add(const Duration(days: 365));
  String? _loadedId;
  bool _saving = false;

  static const _categories = <String, String>{
    'safety': 'Safety buffer',
    'family': 'Family support',
    'education': 'Education',
    'home': 'Home',
    'travel': 'Travel',
    'other': 'Other',
  };

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _current.dispose();
    _essentials.dispose();
    _family.dispose();
    super.dispose();
  }

  void _loadGoal(MoneyGoal goal) {
    if (_loadedId == goal.id) return;
    _loadedId = goal.id;
    _name.text = goal.name;
    _target.text = goal.targetAmount.toString();
    _current.text = goal.currentAmount.toString();
    _essentials.text = goal.monthlyEssentials.toString();
    _family.text = goal.monthlyFamilySupport.toString();
    _category = goal.category;
    _targetDate = goal.targetDate;
  }

  int _number(TextEditingController controller) =>
      int.tryParse(controller.text.replaceAll(',', '').trim()) ?? 0;

  MoneyGoal _draft() => MoneyGoal(
        id: _loadedId ?? '',
        name: _name.text.trim().isEmpty ? 'My money goal' : _name.text.trim(),
        category: _category,
        targetAmount: _number(_target),
        currentAmount: _number(_current),
        targetDate: _targetDate,
        monthlyEssentials: _number(_essentials),
        monthlyFamilySupport: _number(_family),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(moneyGoalProvider.notifier).save(_draft());
      if (!mounted) return;
      setState(() => _loadedId = saved.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goal saved to your account.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this goal. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(moneyGoalProvider).asData?.value ?? const [];
    final goal = goals.isEmpty ? null : goals.first;
    if (goal != null && _loadedId == null) {
      _loadGoal(goal);
    }
    final netPay = ref.watch(paycheckProvider).netCredited;
    final projection = projectGoal(goal: _draft(), monthlyNetPay: netPay);

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Money goal', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Turn this paycheck into a plan.',
                style: PaycheckType.title(),
              ),
              const SizedBox(height: 8),
              Text(
                netPay > 0
                    ? 'The plan uses your confirmed net pay of ${_money(netPay)}.'
                    : 'Confirm a payslip first so ARTH can test this goal against real net pay.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 20),
              _ProjectionBand(projection: projection, hasPay: netPay > 0),
              const SizedBox(height: 26),
              Text('Goal', style: PaycheckType.heading()),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'What are you planning for?',
                  hintText: 'Support my parents or build an emergency fund',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Enter a clear goal name'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.entries.map((entry) {
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    onSelected: (_) => setState(() => _category = entry.key),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MoneyField(
                      controller: _target,
                      label: 'Target amount',
                      requiredPositive: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MoneyField(
                      controller: _current,
                      label: 'Already saved',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _targetDate,
                    firstDate: DateTime.now().add(const Duration(days: 30)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365 * 20)),
                  );
                  if (date != null) setState(() => _targetDate = date);
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  'Target date: ${DateFormat('MMM yyyy').format(_targetDate)}',
                ),
              ),
              const SizedBox(height: 28),
              Text('Monthly commitments', style: PaycheckType.heading()),
              const SizedBox(height: 6),
              Text(
                'Use essential spending, not your entire bank outflow. Family support is optional and stays separate.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _essentials,
                label: 'Rent, food, travel and bills',
                requiredPositive: true,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _family,
                label: 'Monthly family contribution',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 24),
              _PlanGuidance(
                  projection: projection, essentials: _number(_essentials)),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving' : 'Save goal'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: PaycheckColors.ink,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ARTH shows planning ranges, not a recommendation to buy a specific investment product.',
                textAlign: TextAlign.center,
                style: PaycheckType.utility(color: PaycheckColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectionBand extends StatelessWidget {
  const _ProjectionBand({required this.projection, required this.hasPay});

  final GoalProjection projection;
  final bool hasPay;

  @override
  Widget build(BuildContext context) {
    final feasible = hasPay && projection.isFeasible;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PaycheckColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            feasible ? 'TARGET LOOKS FEASIBLE' : 'MONTHLY PLAN CHECK',
            style: PaycheckType.utility(
              color: feasible ? PaycheckColors.matched : Colors.white60,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _money(projection.requiredMonthly),
            style: PaycheckType.display(color: Colors.white),
          ),
          Text(
            'needed each month for ${projection.monthsRemaining} months',
            style: PaycheckType.body(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Text(
            hasPay
                ? '${_money(projection.availableMonthly)} remains after the commitments entered below.'
                : 'Add a confirmed payslip to calculate available monthly money.',
            style: PaycheckType.body(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PlanGuidance extends StatelessWidget {
  const _PlanGuidance({required this.projection, required this.essentials});

  final GoalProjection projection;
  final int essentials;

  @override
  Widget build(BuildContext context) {
    final bufferTarget = essentials * 3;
    final shortfall = -projection.monthlyHeadroom;
    final message = projection.isFeasible
        ? 'Keep at least ${_money(bufferTarget)} as a three-month safety buffer. Then automate ${_money(projection.requiredMonthly)} monthly toward this goal.'
        : 'The current target is short by ${_money(shortfall)} per month. Extend the date, lower the target, or reduce a flexible commitment before choosing an investment product.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: projection.isFeasible
            ? PaycheckColors.matchedSoft
            : PaycheckColors.claimSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            projection.isFeasible ? Icons.route_outlined : Icons.tune_rounded,
            color: projection.isFeasible
                ? PaycheckColors.matched
                : PaycheckColors.claim,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: PaycheckType.bodyStrong())),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.requiredPositive = false,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final bool requiredPositive;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, prefixText: '₹ '),
      validator: (value) {
        final amount = int.tryParse(value ?? '') ?? 0;
        if (requiredPositive && amount <= 0) return 'Enter an amount';
        return null;
      },
      onChanged: (_) => onChanged(),
    );
  }
}

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);
