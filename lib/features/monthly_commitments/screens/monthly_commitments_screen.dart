import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../features/spend_completeness/providers/spend_completeness_provider.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../engine/monthly_commitments_engine.dart';
import '../models/monthly_commitment_models.dart';
import '../providers/monthly_commitments_provider.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

class MonthlyCommitmentsScreen extends ConsumerWidget {
  const MonthlyCommitmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(spendMapProvider).map;
    final saved = ref.watch(monthlyCommitmentsProvider);
    final settings = ref.watch(spendCompletenessProvider);
    final items = map == null
        ? saved.manual
        : MonthlyCommitmentsEngine.resolve(
            map: map,
            settings: settings,
            saved: saved,
          );
    final total = MonthlyCommitmentsEngine.total(items);

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        foregroundColor: PaycheckColors.ink,
        elevation: 0,
        title: Text('Monthly commitments', style: PaycheckType.heading()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCommitment(context, ref),
        backgroundColor: PaycheckColors.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add commitment'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text('What repeats each month.', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'Only confirmed repeats and items you add count here.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/decision-sandbox'),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Test a new commitment'),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: PaycheckColors.ink,
              borderRadius: AppRadius.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly committed',
                    style: PaycheckType.utility(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(_money(total),
                    style: PaycheckType.display(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                    '${items.length} confirmed item${items.length == 1 ? '' : 's'}',
                    style: PaycheckType.utility(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (items.isEmpty)
            Text('Confirm repeats in Spend completeness, or add one yourself.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft))
          else
            for (final item in items) ...[
              _CommitmentRow(
                item: item,
                onTap: item.source == CommitmentSource.manual
                    ? () => _editCommitment(context, ref, existing: item)
                    : null,
                onDelete: item.source == CommitmentSource.manual
                    ? () => ref
                        .read(monthlyCommitmentsProvider.notifier)
                        .delete(item.id)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 16),
          Text(
              'Tracked spending may be incomplete. This is not your bank balance.',
              style: PaycheckType.utility(color: PaycheckColors.inkSoft)),
        ],
      ),
    );
  }

  Future<void> _editCommitment(
    BuildContext context,
    WidgetRef ref, {
    MonthlyCommitment? existing,
  }) async {
    final label = TextEditingController(text: existing?.label ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : '${existing.monthlyAmount}');
    final saved = await showModalBottomSheet<MonthlyCommitment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PaycheckColors.paper,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                existing == null
                    ? 'Add monthly commitment'
                    : 'Edit monthly commitment',
                style: PaycheckType.heading()),
            const SizedBox(height: 16),
            TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Monthly amount', prefixText: '₹ ')),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final monthly = int.tryParse(amount.text) ?? 0;
                if (label.text.trim().isEmpty || monthly <= 0) return;
                Navigator.pop(
                    sheetContext,
                    MonthlyCommitment(
                      id: existing?.id ??
                          'manual_${DateTime.now().microsecondsSinceEpoch}',
                      label: label.text.trim(),
                      monthlyAmount: monthly,
                      nextExpectedDate: existing?.nextExpectedDate ??
                          DateTime.now().add(const Duration(days: 30)),
                      source: CommitmentSource.manual,
                    ));
              },
              child:
                  Text(existing == null ? 'Save commitment' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    amount.dispose();
    if (saved != null) {
      await ref.read(monthlyCommitmentsProvider.notifier).save(saved);
    }
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({required this.item, this.onTap, this.onDelete});

  final MonthlyCommitment item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Material(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: PaycheckColors.line),
              borderRadius: AppRadius.card,
            ),
            child: Row(
              children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item.label, style: PaycheckType.bodyStrong()),
                      const SizedBox(height: 4),
                      Text(
                          item.source == CommitmentSource.manual
                              ? 'Added by you · tap to edit'
                              : 'Confirmed repeat',
                          style: PaycheckType.utility())
                    ])),
                Text(_money(item.monthlyAmount), style: PaycheckType.money()),
                if (onDelete != null)
                  IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Remove commitment'),
              ],
            ),
          ),
        ),
      );
}
