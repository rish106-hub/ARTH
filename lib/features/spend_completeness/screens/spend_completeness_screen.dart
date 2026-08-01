import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/spend_map.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../theme/paycheck_theme.dart';
import '../../../utils/money_format.dart';
import '../engine/spend_completeness_engine.dart';
import '../models/spend_completeness_models.dart';
import '../providers/spend_completeness_provider.dart';

class SpendCompletenessScreen extends ConsumerWidget {
  const SpendCompletenessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(spendMapProvider).map;
    final settings = ref.watch(spendCompletenessProvider);

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        elevation: 0,
        foregroundColor: PaycheckColors.ink,
        title: Text('Spend coverage', style: PaycheckType.heading()),
      ),
      body: map == null || map.isEmpty
          ? const _NoSpendData()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'See what your SMS data proves, what it misses, and which repeats are likely.',
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                  const SizedBox(height: 16),
                  _CoverageReceipt(map: map, settings: settings),
                  const SizedBox(height: 16),
                  _SalarySourceCard(map: map, settings: settings),
                  const SizedBox(height: 16),
                  _MissingSpendCard(settings: settings),
                  const SizedBox(height: 16),
                  _RecurringCard(map: map, settings: settings),
                  const SizedBox(height: 16),
                  _HouseholdCard(map: map, settings: settings),
                  const SizedBox(height: 16),
                  _BudgetCard(map: map, settings: settings),
                ],
              ),
            ),
    );
  }
}

class _NoSpendData extends StatelessWidget {
  const _NoSpendData();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Scan transaction SMS in Spend map first.',
            textAlign: TextAlign.center,
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
        ),
      );
}

class _CoverageReceipt extends StatelessWidget {
  const _CoverageReceipt({required this.map, required this.settings});

  final SpendMap map;
  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context) {
    final sources = SpendCompletenessEngine.salarySources(map);
    final debits =
        map.txns.where((txn) => txn.direction == TxnDirection.debit).length;
    final selected = settings.trustedSalarySourceId;
    final missingLabels =
        settings.missingSources.map((source) => source.label).toList();
    final salaryStatus = selected ??
        (sources.isEmpty
            ? 'No salary credit found'
            : 'Confirm ${sources.length} detected source${sources.length == 1 ? '' : 's'}');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        border: Border.all(color: PaycheckColors.ink, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COVERAGE RECEIPT',
            style: PaycheckType.sectionLabel(color: PaycheckColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('d MMM yyyy, h:mm a').format(map.generatedAt),
            style: PaycheckType.utility(),
          ),
          const SizedBox(height: 16),
          const _ReceiptRule(),
          const SizedBox(height: 12),
          _ReceiptRow(
            label: 'Bank + UPI SMS',
            value: '$debits debit${debits == 1 ? '' : 's'} included',
            color: PaycheckColors.matched,
          ),
          _ReceiptRow(
            label: 'Salary source',
            value: salaryStatus,
            color: selected == null
                ? PaycheckColors.pending
                : PaycheckColors.matched,
          ),
          _ReceiptRow(
            label: 'Declared gaps',
            value: missingLabels.isEmpty
                ? 'None declared'
                : '${missingLabels.length} source${missingLabels.length == 1 ? '' : 's'} missing',
            color: missingLabels.isEmpty
                ? PaycheckColors.inkSoft
                : PaycheckColors.claim,
          ),
          const SizedBox(height: 12),
          const _ReceiptRule(),
          const SizedBox(height: 12),
          Text(
            'No fake coverage percentage. No guessed missing amount.',
            style: PaycheckType.utility(color: PaycheckColors.ink),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRule extends StatelessWidget {
  const _ReceiptRule();

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(
          18,
          (index) => Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: PaycheckColors.line,
            ),
          ),
        ),
      );
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: PaycheckType.body())),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: PaycheckType.bodyStrong(color: color),
              ),
            ),
          ],
        ),
      );
}

class _SalarySourceCard extends ConsumerWidget {
  const _SalarySourceCard({required this.map, required this.settings});

  final SpendMap map;
  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = SpendCompletenessEngine.salarySources(map);
    return _SectionCard(
      eyebrow: 'INCOME SOURCE',
      title: 'Pick the salary account',
      body: 'Only this sender counts as salary income. '
          'The choice stays on this phone.',
      child: sources.isEmpty
          ? Text(
              'No salary credit sender was found in this scan.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            )
          : RadioGroup<String>(
              groupValue: settings.trustedSalarySourceId,
              onChanged: (value) => ref
                  .read(spendCompletenessProvider.notifier)
                  .setTrustedSalarySource(value),
              child: Column(
                children: [
                  for (final source in sources)
                    RadioListTile<String>(
                      value: source.id,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(source.id, style: PaycheckType.bodyStrong()),
                      subtitle: Text(
                        'Latest ${money0(source.latestAmount)} · ${source.months} month${source.months == 1 ? '' : 's'} seen',
                        style: PaycheckType.utility(),
                      ),
                    ),
                  if (settings.trustedSalarySourceId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => ref
                            .read(spendCompletenessProvider.notifier)
                            .setTrustedSalarySource(null),
                        child: const Text('Clear choice'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MissingSpendCard extends ConsumerWidget {
  const _MissingSpendCard({required this.settings});

  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SectionCard(
        eyebrow: 'KNOWN GAPS',
        title: 'What SMS misses',
        body:
            'Mark channels you use. ARTH will flag the map as partial. It will not invent a rupee gap.',
        child: Column(
          children: [
            for (final source in MissingSpendSource.values)
              CheckboxListTile(
                value: settings.missingSources.contains(source),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(source.label, style: PaycheckType.body()),
                onChanged: (value) => ref
                    .read(spendCompletenessProvider.notifier)
                    .setMissingSource(source, value ?? false),
              ),
          ],
        ),
      );
}

class _RecurringCard extends ConsumerWidget {
  const _RecurringCard({required this.map, required this.settings});

  final SpendMap map;
  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = SpendCompletenessEngine.recurringSpend(map);
    final visible = all
        .where((item) => !settings.dismissedRecurringIds.contains(item.id))
        .toList();
    return _SectionCard(
      eyebrow: 'LOCAL PATTERNS',
      title: 'Likely recurring spend',
      body:
          'A repeat needs at least two similar monthly debits. Confirmed items stay local.',
      trailing: settings.dismissedRecurringIds.isEmpty
          ? null
          : TextButton(
              onPressed: () => ref
                  .read(spendCompletenessProvider.notifier)
                  .restoreDismissedRecurring(),
              child: const Text('Restore hidden'),
            ),
      child: visible.isEmpty
          ? Text(
              all.isEmpty
                  ? 'No stable monthly repeats yet.'
                  : 'All detected repeats are hidden.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  if (index > 0) const Divider(height: 24),
                  _RecurringRow(
                    item: visible[index],
                    confirmed: settings.confirmedRecurringIds
                        .contains(visible[index].id),
                  ),
                ],
              ],
            ),
    );
  }
}

class _RecurringRow extends ConsumerWidget {
  const _RecurringRow({required this.item, required this.confirmed});

  final RecurringSpend item;
  final bool confirmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.label, style: PaycheckType.bodyStrong()),
              ),
              Text(
                money0(item.typicalAmount),
                style: PaycheckType.money(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.kind.label} · ${item.occurrences} months · next near ${DateFormat('d MMM').format(item.nextExpectedDate)}',
            style: PaycheckType.utility(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (confirmed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: PaycheckColors.matchedSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Confirmed',
                    style: PaycheckType.utility(color: PaycheckColors.matched),
                  ),
                )
              else
                TextButton(
                  onPressed: () => ref
                      .read(spendCompletenessProvider.notifier)
                      .confirmRecurring(item.id),
                  child: const Text('Confirm'),
                ),
              TextButton(
                onPressed: () => ref
                    .read(spendCompletenessProvider.notifier)
                    .dismissRecurring(item.id),
                child: const Text('Not recurring'),
              ),
            ],
          ),
        ],
      );
}

class _HouseholdCard extends ConsumerWidget {
  const _HouseholdCard({required this.map, required this.settings});

  final SpendMap map;
  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = settings.household;
    final householdIncome = map.monthlyIncome + plan.otherMonthlyIncome;
    return _SectionCard(
      eyebrow: 'OPTIONAL',
      title: 'Shared household',
      body:
          'Plan with one other person. ARTH does not merge logins, inboxes, or transaction data.',
      trailing: Switch(
        value: plan.enabled,
        onChanged: (enabled) =>
            ref.read(spendCompletenessProvider.notifier).setHousehold(
                  HouseholdPlan(
                    enabled: enabled,
                    memberName: plan.memberName,
                    otherMonthlyIncome: plan.otherMonthlyIncome,
                    sharedEssentials: plan.sharedEssentials,
                    yourSharePercent: plan.yourSharePercent,
                  ),
                ),
      ),
      child: !plan.enabled
          ? Text(
              'Off. Your Spend map remains personal.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            )
          : Column(
              children: [
                _MetricRow(
                  label: 'Household monthly income',
                  value: money0(householdIncome),
                ),
                _MetricRow(
                  label: 'Shared rent + essentials',
                  value: money0(plan.sharedEssentials),
                ),
                _MetricRow(
                  label: 'Your ${plan.yourSharePercent}% share',
                  value: money0(plan.yourSharedCost),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _editHousehold(context, ref, plan),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit household plan'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.map, required this.settings});

  final SpendMap map;
  final SpendCompletenessState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = SpendCompletenessEngine.budgetSuggestions(map);
    return _SectionCard(
      eyebrow: 'SOFT LIMITS',
      title: 'Category budgets',
      body:
          'Suggestions use your observed monthly trend. They warn you. They do not block spending.',
      child: suggestions.isEmpty
          ? Text(
              'Not enough categorized spend yet.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            )
          : Column(
              children: [
                for (var index = 0; index < suggestions.length; index++) ...[
                  if (index > 0) const Divider(height: 24),
                  _BudgetRow(
                    suggestion: suggestions[index],
                    budget:
                        settings.categoryBudgets[suggestions[index].category],
                  ),
                ],
              ],
            ),
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.suggestion, required this.budget});

  final CategoryBudgetSuggestion suggestion;
  final int? budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = budget;
    final ratio = limit == null || limit <= 0
        ? 0.0
        : suggestion.projectedMonthSpend / limit;
    final warning = ratio >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                SpendCategory.label(suggestion.category),
                style: PaycheckType.bodyStrong(),
              ),
            ),
            if (limit != null)
              Text(
                '${money0(suggestion.currentMonthSpend)} / ${money0(limit)}',
                style: PaycheckType.money(
                  color: warning ? PaycheckColors.claim : PaycheckColors.ink,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          limit == null
              ? 'Observed average ${money0(suggestion.historicalMonthlyAverage)} per month'
              : 'Projected ${money0(suggestion.projectedMonthSpend)} this month',
          style: PaycheckType.utility(),
        ),
        const SizedBox(height: 8),
        if (limit == null)
          OutlinedButton(
            onPressed: () =>
                ref.read(spendCompletenessProvider.notifier).setCategoryBudget(
                      suggestion.category,
                      suggestion.suggestedLimit,
                    ),
            child: Text('Use ${money0(suggestion.suggestedLimit)} limit'),
          )
        else
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: ratio.clamp(0, 1),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: PaycheckColors.surfaceMuted,
                  color:
                      warning ? PaycheckColors.claim : PaycheckColors.contract,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => _editBudget(
                  context,
                  ref,
                  suggestion.category,
                  limit,
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: PaycheckType.body())),
            Text(value, style: PaycheckType.money()),
          ],
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.child,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String body;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
        color: PaycheckColors.paper,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: PaycheckColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: PaycheckType.sectionLabel()),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(title, style: PaycheckType.heading())),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

Future<void> _editHousehold(
  BuildContext context,
  WidgetRef ref,
  HouseholdPlan current,
) async {
  final name = TextEditingController(text: current.memberName);
  final income = TextEditingController(
    text: current.otherMonthlyIncome > 0
        ? current.otherMonthlyIncome.toString()
        : '',
  );
  final essentials = TextEditingController(
    text:
        current.sharedEssentials > 0 ? current.sharedEssentials.toString() : '',
  );
  final share =
      TextEditingController(text: current.yourSharePercent.toString());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PaycheckColors.paper,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Household plan', style: PaycheckType.h2()),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Other person (optional)',
              ),
            ),
            const SizedBox(height: 12),
            _NumberField(
              controller: income,
              label: 'Their monthly income',
            ),
            const SizedBox(height: 12),
            _NumberField(
              controller: essentials,
              label: 'Total shared rent + essentials',
            ),
            const SizedBox(height: 12),
            _NumberField(
              controller: share,
              label: 'Your share (%)',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final shareValue =
                      (int.tryParse(share.text) ?? 50).clamp(0, 100);
                  await ref
                      .read(spendCompletenessProvider.notifier)
                      .setHousehold(
                        HouseholdPlan(
                          enabled: true,
                          memberName: name.text.trim(),
                          otherMonthlyIncome: int.tryParse(income.text) ?? 0,
                          sharedEssentials: int.tryParse(essentials.text) ?? 0,
                          yourSharePercent: shareValue,
                        ),
                      );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save household plan'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  name.dispose();
  income.dispose();
  essentials.dispose();
  share.dispose();
}

Future<void> _editBudget(
  BuildContext context,
  WidgetRef ref,
  String category,
  int current,
) async {
  final controller = TextEditingController(text: current.toString());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PaycheckColors.paper,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${SpendCategory.label(category)} limit',
            style: PaycheckType.h2(),
          ),
          const SizedBox(height: 16),
          _NumberField(controller: controller, label: 'Monthly soft limit'),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await ref
                      .read(spendCompletenessProvider.notifier)
                      .setCategoryBudget(category, null);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Remove'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(spendCompletenessProvider.notifier)
                      .setCategoryBudget(
                        category,
                        int.tryParse(controller.text),
                      );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save limit'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      );
}
