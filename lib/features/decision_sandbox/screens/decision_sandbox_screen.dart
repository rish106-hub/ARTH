import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/analytics_provider.dart';
import '../../../providers/money_goal_provider.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../models/money_goal.dart';
import '../../../services/analytics_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../engine/decision_sandbox_engine.dart';
import '../models/decision_sandbox_models.dart';
import '../providers/decision_sandbox_provider.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

class DecisionSandboxScreen extends ConsumerWidget {
  const DecisionSandboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(spendMapProvider).map;
    final scenarios = ref.watch(decisionSandboxProvider).scenarios;
    final goals = ref.watch(moneyGoalProvider).asData?.value ?? const [];
    final room = map?.monthlyNet ?? 0;
    final income = map?.monthlyIncome;

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        foregroundColor: PaycheckColors.ink,
        elevation: 0,
        title: Text('Decision sandbox', style: PaycheckType.heading()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Test it before it costs you.', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'Private estimate from your tracked money. Not an affordability decision.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 24),
          Text('Start a scenario', style: PaycheckType.heading()),
          const SizedBox(height: 12),
          for (final kind in DecisionKind.values) ...[
            _TemplateRow(
              kind: kind,
              onTap: () => _openEditor(
                context,
                ref,
                kind: kind,
                trackedRoom: room,
                income: income,
                goals: goals,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),
          Text('Saved scenarios', style: PaycheckType.heading()),
          const SizedBox(height: 12),
          if (scenarios.isEmpty)
            Text('No saved decisions yet.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft))
          else
            for (final scenario in scenarios) ...[
              _ScenarioRow(
                scenario: scenario,
                onTap: () => _openEditor(
                  context,
                  ref,
                  kind: scenario.kind,
                  existing: scenario,
                  trackedRoom: room,
                  income: income,
                  goals: goals,
                ),
                onDelete: () => ref
                    .read(decisionSandboxProvider.notifier)
                    .delete(scenario.id),
                onDuplicate: () => ref
                    .read(decisionSandboxProvider.notifier)
                    .duplicate(scenario),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required DecisionKind kind,
    required int trackedRoom,
    required int? income,
    required List<MoneyGoal> goals,
    DecisionScenario? existing,
  }) async {
    final saved = await showModalBottomSheet<DecisionScenario>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaycheckColors.paper,
      showDragHandle: true,
      builder: (_) => _DecisionEditor(
        kind: kind,
        existing: existing,
        trackedRoom: trackedRoom,
        income: income,
        goals: goals,
      ),
    );
    if (saved == null) return;
    await ref.read(decisionSandboxProvider.notifier).save(saved);

    // Recomputed rather than threaded out of the editor: the goal shift is the
    // one thing worth measuring here — whether testing a decision actually told
    // the user something about a goal they care about.
    final goal = saved.goalId == null
        ? null
        : goals.where((g) => g.id == saved.goalId).firstOrNull;
    final projection = DecisionSandboxEngine.project(
      scenario: saved,
      trackedMonthlyRoom: trackedRoom,
      goal: goal,
      monthlyIncome: income,
    );
    await ref.read(analyticsProvider).decisionScenarioSaved(
          kind: _analyticsKind(kind),
          isNew: existing == null,
          goalFinishChangeMonths: projection.goalFinishChangeMonths,
        );
  }

  static DecisionAnalyticsKind _analyticsKind(DecisionKind kind) =>
      switch (kind) {
        DecisionKind.moveForWork => DecisionAnalyticsKind.moveForWork,
        DecisionKind.buyVehicle => DecisionAnalyticsKind.buyVehicle,
        DecisionKind.changeJobs => DecisionAnalyticsKind.changeJobs,
      };
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.kind, required this.onTap});
  final DecisionKind kind;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(kind.label, style: PaycheckType.bodyStrong()),
                    const SizedBox(height: 4),
                    Text(kind.detail, style: PaycheckType.utility())
                  ])),
              const Icon(Icons.chevron_right_rounded)
            ]),
          ),
        ),
      );
}

class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow(
      {required this.scenario,
      required this.onTap,
      required this.onDelete,
      required this.onDuplicate});
  final DecisionScenario scenario;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  @override
  Widget build(BuildContext context) => Material(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        child: ListTile(
          onTap: onTap,
          title: Text(scenario.name, style: PaycheckType.bodyStrong()),
          subtitle: Text(
              '${scenario.kind.label} · ${scenario.monthlyRoomChange >= 0 ? '+' : ''}${_money(scenario.monthlyRoomChange)}/mo',
              style: PaycheckType.utility()),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: onDuplicate,
              tooltip: 'Duplicate scenario',
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete scenario',
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
      );
}

class _DecisionEditor extends StatefulWidget {
  const _DecisionEditor(
      {required this.kind,
      required this.existing,
      required this.trackedRoom,
      required this.income,
      required this.goals});
  final DecisionKind kind;
  final DecisionScenario? existing;
  final int trackedRoom;
  final int? income;
  final List<MoneyGoal> goals;
  @override
  State<_DecisionEditor> createState() => _DecisionEditorState();
}

class _DecisionEditorState extends State<_DecisionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _income;
  late final TextEditingController _current;
  late final TextEditingController _proposed;
  late final TextEditingController _oneOff;
  String? _goalId;

  @override
  void initState() {
    super.initState();
    final current = widget.existing;
    _name = TextEditingController(text: current?.name ?? widget.kind.label);
    _income =
        TextEditingController(text: '${current?.monthlyIncomeChange ?? 0}');
    _current =
        TextEditingController(text: '${current?.currentMonthlyCost ?? 0}');
    _proposed =
        TextEditingController(text: '${current?.proposedMonthlyCost ?? 0}');
    _oneOff = TextEditingController(text: '${current?.oneOffCost ?? 0}');
    _goalId = current?.goalId;
  }

  @override
  void dispose() {
    _name.dispose();
    _income.dispose();
    _current.dispose();
    _proposed.dispose();
    _oneOff.dispose();
    super.dispose();
  }

  int _number(TextEditingController value) => int.tryParse(value.text) ?? 0;
  @override
  Widget build(BuildContext context) {
    MoneyGoal? selectedGoal;
    for (final goal in widget.goals) {
      if (goal.id == _goalId) {
        selectedGoal = goal;
        break;
      }
    }
    final scenario = DecisionScenario(
        id: widget.existing?.id ??
            'scenario_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim().isEmpty ? widget.kind.label : _name.text.trim(),
        kind: widget.kind,
        monthlyIncomeChange: _number(_income),
        currentMonthlyCost: _number(_current),
        proposedMonthlyCost: _number(_proposed),
        oneOffCost: _number(_oneOff),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        goalId: _goalId);
    final projection = DecisionSandboxEngine.project(
        scenario: scenario,
        trackedMonthlyRoom: widget.trackedRoom,
        goal: selectedGoal,
        monthlyIncome: widget.income);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.kind.label, style: PaycheckType.title()),
            const SizedBox(height: 8),
            Text(
              'Known room: ${_money(widget.trackedRoom)} tracked monthly.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 20),
            _field(_name, 'Scenario name'),
            _field(_income, 'Monthly income change', signed: true),
            _field(_current, 'Current monthly cost'),
            _field(_proposed, 'Proposed monthly cost'),
            _field(_oneOff, 'One-off cost'),
            if (widget.goals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String?>(
                  initialValue: _goalId,
                  decoration: const InputDecoration(labelText: 'Goal to test'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No goal'),
                    ),
                    ...widget.goals.map(
                      (goal) => DropdownMenuItem<String?>(
                        value: goal.id,
                        child: Text(goal.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _goalId = value),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: PaycheckColors.contractSoft,
                borderRadius: AppRadius.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Result', style: PaycheckType.bodyStrong()),
                  const SizedBox(height: 8),
                  Text(
                    'Tracked room change: ${projection.monthlyRoomChange >= 0 ? '+' : ''}${_money(projection.monthlyRoomChange)} / month',
                  ),
                  Text(
                      'After change: ${_money(projection.projectedTrackedRoom)}'),
                  if (projection.monthsToAbsorbOneOffCost != null)
                    Text(
                        'One-off cost: ${projection.monthsToAbsorbOneOffCost} months'),
                  if (projection.goalFinishChangeMonths != null)
                    Text(
                        'First goal: ${projection.goalFinishChangeMonths! >= 0 ? '+' : ''}${projection.goalFinishChangeMonths} months'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, scenario),
              child: const Text('Save scenario'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
          {bool signed = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(signed: signed),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: label, prefixText: signed ? '₹ ' : '₹ ')));
}
