import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/spend_map.dart';
import '../models/spend_scan_period_copy.dart';
import '../providers/custom_spend_categories_provider.dart';
import '../providers/other_income_provider.dart';
import '../providers/spend_map_adjustments_provider.dart';
import '../providers/spend_map_provider.dart';
import '../services/merchant_category_rules.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../utils/money_format.dart';
import '../widgets/premium_ui.dart';

class SpendInsightsScreen extends ConsumerWidget {
  const SpendInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendMapProvider);

    // Fires exactly once per transition into "awaiting answer" — right after
    // SMS permission is granted for the first time. Shows the one-time
    // follow-up question before the SMS read actually happens.
    ref.listen(spendMapProvider, (previous, next) {
      final wasAwaiting = previous?.awaitingOtherIncomeAnswer ?? false;
      if (!wasAwaiting && next.awaitingOtherIncomeAnswer) {
        _askOtherIncomeQuestion(context, ref);
      }
    });

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        elevation: 0,
        foregroundColor: PaycheckColors.ink,
        title: Text('Spend map', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ArthDisclosure(
                label: 'Transaction SMS only, parsed on this device',
                icon: Icons.lock_outline,
                detail:
                    'ARTH reads only bank and UPI transaction SMS. Personal messages are ignored. Parsing stays on-device, and the resulting transaction history is encrypted and backed up to your ARTH account.',
              ),
              const SizedBox(height: 12),
              _PeriodPicker(
                selected: state.selectedPeriod,
                onSelected: (period) =>
                    ref.read(spendMapProvider.notifier).selectPeriod(period),
              ),
              const SizedBox(height: 20),
              if (state.loading)
                const _Loading()
              else if (state.permissionDenied)
                _PermissionCard(
                    onRetry: () => ref.read(spendMapProvider.notifier).scan())
              else if (state.error != null)
                _ErrorCard(
                  message: state.error!,
                  onRetry: () => ref.read(spendMapProvider.notifier).scan(),
                )
              else if (!state.hasData)
                _EmptyCard(
                  period: state.selectedPeriod,
                  onScan: () => ref.read(spendMapProvider.notifier).scan(),
                )
              else
                _Insights(
                  map: state.map!,
                  period: state.selectedPeriod,
                  showRecalculationNotice: state.showRecalculationNotice,
                  onDismissRecalculationNotice: () => ref
                      .read(spendMapProvider.notifier)
                      .dismissRecalculationNotice(),
                ),
              if (state.hasData && !state.loading) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => ref.read(spendMapProvider.notifier).scan(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rescan SMS'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One-time "any other income to add?" prompt shown right after SMS
/// permission is granted, before the inbox is actually read. Answering either
/// way (yes/no) marks the question asked and resumes the paused scan.
Future<void> _askOtherIncomeQuestion(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Any other income?'),
      content: const Text(
        'Freelance work, rent, a side business? '
        'Kept on this device only.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await ref.read(otherIncomeProvider.notifier).markAsked();
            await ref
                .read(spendMapProvider.notifier)
                .resumeScanAfterOtherIncomeAnswer();
          },
          child: const Text('No, that\'s all'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await ref.read(otherIncomeProvider.notifier).markAsked();
            if (context.mounted) {
              await _editOtherIncome(context, ref);
            }
            if (context.mounted) {
              await ref
                  .read(spendMapProvider.notifier)
                  .resumeScanAfterOtherIncomeAnswer();
            }
          },
          child: const Text('Yes, add it'),
        ),
      ],
    ),
  );
}

/// Bottom sheet for adding/removing manual "other income" sources. Reusable
/// both from the first-time follow-up question and from the persistent "Edit"
/// affordance on the insights screen.
Future<void> _editOtherIncome(BuildContext context, WidgetRef ref) {
  final labelController = TextEditingController();
  final amountController = TextEditingController();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final sources = ref.watch(otherIncomeProvider);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child:
                            Text('Other income', style: PaycheckType.title()),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 14, color: PaycheckColors.inkSoft),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Stays on this device only — never sent to our servers.',
                          style: PaycheckType.utility(
                              color: PaycheckColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final source in sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(source.label,
                                style: PaycheckType.bodyStrong()),
                          ),
                          Text(money0(source.monthlyAmount),
                              style: PaycheckType.body()),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => ref
                                .read(otherIncomeProvider.notifier)
                                .remove(source.id),
                          ),
                        ],
                      ),
                    ),
                  if (sources.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: labelController,
                          decoration: const InputDecoration(
                            labelText: 'Source (e.g. Freelance)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '₹ / month',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final amount = int.tryParse(
                          amountController.text.replaceAll(',', '').trim(),
                        );
                        if (labelController.text.trim().isEmpty ||
                            amount == null ||
                            amount <= 0) {
                          return;
                        }
                        await ref
                            .read(otherIncomeProvider.notifier)
                            .add(labelController.text, amount);
                        labelController.clear();
                        amountController.clear();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add source'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _editMonthlyIncome(
  BuildContext context,
  WidgetRef ref,
  SpendMap map,
  SpendScanPeriod period,
) {
  final controller = TextEditingController(
    text: map.primaryIncomeIsManual
        ? map.primaryMonthlyIncome.toString()
        : map.observedPrimaryMonthlyIncome > 0
            ? map.observedPrimaryMonthlyIncome.toString()
            : '',
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      period.avgMonthlyIncomeTitle,
                      style: PaycheckType.title(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                period.incomeTrendCaption(
                  sourceLabel: map.primaryIncomeSourceLabel,
                  monthsWithSalary: map.salaryMonthsWithData,
                  includesOtherIncome: map.hasOtherIncome,
                  isManual: map.primaryIncomeIsManual,
                ),
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 16),
              if (map.salaryCredited > 0)
                _IncomeSourceRow(
                  label: 'Salary SMS average',
                  amount: map.observedPrimaryMonthlyIncome,
                  detail:
                      '${map.salaryMonthsWithData} month(s) with a salary credit',
                  onUse: () async {
                    await ref
                        .read(spendMapAdjustmentsProvider.notifier)
                        .clearManualPrimaryIncome();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              if (map.fallbackMonthlyIncome != null &&
                  map.fallbackMonthlyIncome! > 0 &&
                  map.salaryCredited <= 0)
                _IncomeSourceRow(
                  label: 'Payslip estimate',
                  amount: map.fallbackMonthlyIncome!,
                  detail: 'From your confirmed payslip or CTC',
                  onUse: () async {
                    await ref
                        .read(spendMapAdjustmentsProvider.notifier)
                        .clearManualPrimaryIncome();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 12),
              Text('Your monthly income', style: PaycheckType.bodyStrong()),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'Enter take-home monthly income',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(spendMapAdjustmentsProvider.notifier)
                            .clearManualPrimaryIncome();
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('Use detected figure'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final amount = int.tryParse(
                          controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
                        );
                        if (amount == null || amount <= 0) return;
                        await ref
                            .read(spendMapAdjustmentsProvider.notifier)
                            .setManualPrimaryIncome(amount);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  if (context.mounted) {
                    await _editOtherIncome(context, ref);
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(
                  map.hasOtherIncome
                      ? 'Edit other income (${money0(map.otherMonthlyIncome)}/mo)'
                      : 'Add other income (freelance, rent…)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _editMonthlySpend(
  BuildContext context,
  WidgetRef ref,
  SpendMap map,
  SpendScanPeriod period,
) {
  final controller = TextEditingController(
    text: map.spendIsManual
        ? map.monthlySpend.toString()
        : map.observedMonthlySpend > 0
            ? map.observedMonthlySpend.toString()
            : '',
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      period.avgMonthlySpendTitle,
                      style: PaycheckType.title(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                period.spendTrendCaption(
                  monthsWithSpend: map.spendMonthsWithData,
                  totalTransactions: map.txns
                      .where((t) => t.direction == TxnDirection.debit)
                      .length,
                ),
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 16),
              _IncomeSourceRow(
                label: 'SMS trend average',
                amount: map.observedMonthlySpend,
                detail:
                    '${money0(map.totalSpent)} total across ${map.spendMonthsWithData} month(s) with spend',
                onUse: () async {
                  await ref
                      .read(spendMapAdjustmentsProvider.notifier)
                      .clearManualMonthlySpend();
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              const SizedBox(height: 12),
              Text('Your monthly spend', style: PaycheckType.bodyStrong()),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'Enter average monthly spend',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(spendMapAdjustmentsProvider.notifier)
                            .clearManualMonthlySpend();
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('Use SMS trend'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final amount = int.tryParse(
                          controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
                        );
                        if (amount == null || amount <= 0) return;
                        await ref
                            .read(spendMapAdjustmentsProvider.notifier)
                            .setManualMonthlySpend(amount);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _IncomeSourceRow extends StatelessWidget {
  const _IncomeSourceRow({
    required this.label,
    required this.amount,
    required this.detail,
    required this.onUse,
  });

  final String label;
  final int amount;
  final String detail;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.control,
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: PaycheckType.bodyStrong()),
                Text(detail,
                    style: PaycheckType.utility(color: PaycheckColors.inkSoft)),
              ],
            ),
          ),
          Text(money0(amount), style: PaycheckType.bodyStrong()),
          TextButton(onPressed: onUse, child: const Text('Use')),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading & categorising your SMS…'),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onScan, required this.period});
  final VoidCallback onScan;
  final SpendScanPeriod period;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 32, color: PaycheckColors.contract),
          const SizedBox(height: 12),
          Text('Build your spend map', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'From ${period.windowPhrase} of bank and UPI SMS.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const ArthDisclosure(
            label: 'What the scan works out',
            detail:
                'ARTH detects salary credits and spends, separates internal transfers from real expenses, and estimates what you can realistically save each month.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PaycheckColors.ink,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onScan,
              child: const Text('Scan my SMS'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sms_failed_outlined,
              size: 32, color: PaycheckColors.claim),
          const SizedBox(height: 12),
          Text('SMS access needed', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(
            'Grant SMS access to build your spend map.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const ArthDisclosure(
            label: 'Already denied it?',
            detail:
                'Nothing leaves your phone during parsing. If the prompt no longer appears, enable SMS under Settings › Apps › ARTH › Permissions, then try again.',
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Could not scan', style: PaycheckType.title()),
          const SizedBox(height: 8),
          Text(message,
              style: PaycheckType.body(color: PaycheckColors.inkSoft)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final SpendScanPeriod selected;
  final ValueChanged<SpendScanPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ANALYSIS WINDOW', style: PaycheckType.utility()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SpendScanPeriod.values.map((period) {
            return ChoiceChip(
              label: Text(period.pickerLabel),
              selected: selected == period,
              onSelected: (_) => onSelected(period),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 8),
        Text(
          'Income and spend averages use SMS from ${selected.windowPhrase}. '
          '3 months is a useful recent baseline.',
          style: PaycheckType.utility(color: PaycheckColors.contract),
        ),
      ],
    );
  }
}

class _Insights extends ConsumerWidget {
  const _Insights({
    required this.map,
    required this.period,
    required this.showRecalculationNotice,
    required this.onDismissRecalculationNotice,
  });
  final SpendMap map;
  final SpendScanPeriod period;
  final bool showRecalculationNotice;
  final VoidCallback onDismissRecalculationNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unclear = map.txns.indexed
        .where(
          (entry) =>
              entry.$2.direction == TxnDirection.debit &&
              entry.$2.category == SpendCategory.other,
        )
        .toList(growable: false);
    final incomeCaption = period.incomeTrendCaption(
      sourceLabel: map.primaryIncomeSourceLabel,
      monthsWithSalary: map.salaryMonthsWithData,
      includesOtherIncome: map.hasOtherIncome,
      isManual: map.primaryIncomeIsManual,
    );
    final spendCaption = period.spendTrendCaption(
      monthsWithSpend: map.spendMonthsWithData,
      totalTransactions:
          map.txns.where((t) => t.direction == TxnDirection.debit).length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRecalculationNotice) ...[
          _RecalculationNotice(onDismiss: onDismissRecalculationNotice),
          const SizedBox(height: 16),
        ],
        _SavingsHero(map: map, period: period),
        const SizedBox(height: 16),
        _CoverageEntryCard(map: map),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EditableStatTile(
                label: period.avgMonthlyIncomeTitle,
                caption: incomeCaption,
                value: money0(map.monthlyIncome),
                color: PaycheckColors.contract,
                edited: map.primaryIncomeIsManual || map.hasOtherIncome,
                onTap: () => _editMonthlyIncome(context, ref, map, period),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EditableStatTile(
                label: period.avgMonthlySpendTitle,
                caption: spendCaption,
                value: money0(map.monthlySpend),
                color: PaycheckColors.claim,
                edited: map.spendIsManual,
                onTap: () => _editMonthlySpend(context, ref, map, period),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Where it goes', style: PaycheckType.heading()),
        const SizedBox(height: 12),
        _CategoryPie(map: map),
        const SizedBox(height: 16),
        _CategoryBars(map: map),
        const SizedBox(height: 24),
        Text('Month by month', style: PaycheckType.heading()),
        const SizedBox(height: 4),
        Text(
          'Spend vs income per month',
          style: PaycheckType.utility(color: PaycheckColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _MonthlyTrend(map: map),
        const SizedBox(height: 24),
        Text('Forecast', style: PaycheckType.heading()),
        const SizedBox(height: 12),
        _ForecastCard(map: map),
        const SizedBox(height: 24),
        Text('Transactions', style: PaycheckType.heading()),
        const SizedBox(height: 4),
        Text(
          'Tap any row to read the original SMS.',
          style: PaycheckType.utility(color: PaycheckColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _TransactionList(map: map),
        if (unclear.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${unclear.length} unclear transaction${unclear.length == 1 ? '' : 's'}',
                  style: PaycheckType.heading(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Review only these items. Everything else is already categorized.',
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _reviewUnclearSwipe(context, unclear),
                  icon: const Icon(Icons.rule_folder_outlined),
                  label: const Text('Review categories'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/money-goal'),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Build a savings plan'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${map.txns.length} transactions across ${map.observedMonths} month(s), '
          'ending ${DateFormat('d MMM').format(map.windowEnd)}.',
          style: PaycheckType.utility(),
        ),
      ],
    );
  }
}

class _RecalculationNotice extends StatelessWidget {
  const _RecalculationNotice({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_rounded, color: PaycheckColors.contract),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your totals were recalculated',
                    style: PaycheckType.bodyStrong()),
                const SizedBox(height: 4),
                Text(
                  'Spend and savings may look different.',
                  style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                ),
                const ArthDisclosure(
                  label: 'What changed',
                  detail:
                      'Card transfers and duplicate transactions are now handled more accurately, so a bill paid from another account is no longer counted twice.',
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageEntryCard extends StatelessWidget {
  const _CoverageEntryCard({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: PaycheckColors.contractSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: PaycheckColors.contract,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Check spend coverage',
                      style: PaycheckType.bodyStrong()),
                  const SizedBox(height: 4),
                  Text(
                    '${map.txns.length} SMS transactions. Mark missing channels and review repeats.',
                    style: PaycheckType.utility(),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open spend coverage',
              onPressed: () => context.push('/spend-map/coverage'),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      );
}

/// Full-screen, one-card-at-a-time review: swipe away to skip, tap a category
/// to file it and advance. Designed to cut the cognitive load of categorizing
/// several unclear transactions at once — one small decision at a time, with
/// motion that makes progress feel tangible.
Future<void> _reviewUnclearSwipe(
  BuildContext context,
  List<(int, FinanceTxn)> unclear,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _SwipeReviewScreen(unclear: unclear),
    ),
  );
}

class _SwipeReviewScreen extends ConsumerStatefulWidget {
  const _SwipeReviewScreen({required this.unclear});
  final List<(int, FinanceTxn)> unclear;

  @override
  ConsumerState<_SwipeReviewScreen> createState() => _SwipeReviewScreenState();
}

class _SwipeReviewScreenState extends ConsumerState<_SwipeReviewScreen> {
  int _index = 0;
  int _resolved = 0;

  Future<void> _categorize(int txnIndex, String category) async {
    await ref.read(spendMapProvider.notifier).recategorize(txnIndex, category);
    _advance();
  }

  void _advance() {
    setState(() {
      _index += 1;
      _resolved += 1;
    });
  }

  void _skip() => setState(() => _index += 1);

  @override
  Widget build(BuildContext context) {
    final total = widget.unclear.length;
    final done = _index >= total;
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        elevation: 0,
        foregroundColor: PaycheckColors.ink,
        title: Text('Review categories', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              if (!done) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _resolved / total,
                          minHeight: 6,
                          backgroundColor: PaycheckColors.line,
                          color: PaycheckColors.matched,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${_index + 1} of $total',
                        style: PaycheckType.utility()),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Swipe to skip for now, or tap a category to file it.',
                  style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                ),
              ],
              Expanded(
                child: Center(
                  child: done
                      ? _SwipeReviewDone(resolved: _resolved, total: total)
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.15, 0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: FadeTransition(
                                opacity: animation, child: child),
                          ),
                          child: Dismissible(
                            key: ValueKey(widget.unclear[_index].$1),
                            direction: DismissDirection.horizontal,
                            onDismissed: (_) => _skip(),
                            background: const _SwipeHint(
                              alignment: Alignment.centerLeft,
                              icon: Icons.arrow_back_rounded,
                            ),
                            secondaryBackground: const _SwipeHint(
                              alignment: Alignment.centerRight,
                              icon: Icons.arrow_forward_rounded,
                            ),
                            child: _SwipeReviewCard(
                              txn: widget.unclear[_index].$2,
                              onCategory: (category) => _categorize(
                                  widget.unclear[_index].$1, category),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.alignment, required this.icon});
  final Alignment alignment;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PaycheckColors.line,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: PaycheckColors.inkSoft),
    );
  }
}

void _showInsuranceTypeDialog(
  BuildContext context,
  ValueChanged<String> onSelected,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Insurance type',
            style: PaycheckType.heading(),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(sheetContext);
              onSelected(SpendCategory.insuranceCar);
            },
            child: const Text('Car insurance'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(sheetContext);
              onSelected(SpendCategory.insuranceBike);
            },
            child: const Text('Bike insurance'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(sheetContext);
              onSelected(SpendCategory.insuranceHealth);
            },
            child: const Text('Health insurance'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(sheetContext);
              onSelected(SpendCategory.insuranceLife);
            },
            child: const Text('Life insurance'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(sheetContext);
              onSelected(SpendCategory.insuranceOther);
            },
            child: const Text('Other insurance'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Skip'),
          ),
        ],
      ),
    ),
  );
}

class _SwipeReviewCard extends StatelessWidget {
  const _SwipeReviewCard({required this.txn, required this.onCategory});
  final FinanceTxn txn;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: PaycheckColors.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PaycheckColors.line),
              boxShadow: [
                BoxShadow(
                  color: PaycheckColors.ink.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(money0(txn.amount), style: PaycheckType.display()),
                const SizedBox(height: 8),
                Text(
                  txn.merchant?.trim().isNotEmpty == true
                      ? txn.merchant!
                      : (txn.sender ?? 'Unknown'),
                  style: PaycheckType.bodyStrong(),
                ),
                Text(
                  '${DateFormat('d MMM, h:mm a').format(txn.date)} · ${txn.sender ?? 'unknown'}',
                  style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                ),
                if (txn.bodyPreview?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: PaycheckColors.canvas,
                      borderRadius: AppRadius.control,
                    ),
                    child:
                        Text(txn.bodyPreview!, style: PaycheckType.utility()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _CategoryChips(onCategory: onCategory),
        ],
      ),
    );
  }
}

/// Asks for a category name. Returns the raw text so the caller decides whether
/// it names a built-in category or a new one.
class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('custom_category_field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'Income tax',
            ),
            onSubmitted: (_) => _submit(),
          ),
          Text(
            'It stays clickable for future transactions.',
            style: PaycheckType.utility(color: PaycheckColors.inkSoft),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save_custom_category'),
          onPressed: _submit,
          child: const Text('Save and file'),
        ),
      ],
    );
  }
}

/// The category picker. Shared by the unclear-transaction review and the
/// "change category" action on a transaction, so both offer the same choices.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.onCategory, this.selected});

  final ValueChanged<String> onCategory;

  /// Current category, highlighted when re-filing an already-categorised
  /// transaction. Null while reviewing an unclear one.
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The picker provider yields the built-ins the user can file into plus the
    // categories they created. `other` is absent: it is the state they are
    // filing away from, and the parent insurance entry opens the sub-type sheet
    // instead of applying directly.
    final categories = ref.watch(spendCategoryPickerProvider);
    final customLabels = {
      for (final category in ref.watch(customSpendCategoriesProvider))
        category.id: category.label,
    };
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in categories)
          ActionChip(
            avatar: Icon(_iconFor(category), size: 16),
            label:
                Text(customLabels[category] ?? SpendCategory.label(category)),
            backgroundColor:
                _isSelected(category) ? PaycheckColors.matchedSoft : null,
            onPressed: () {
              if (category == SpendCategory.insurance) {
                _showInsuranceTypeDialog(context, onCategory);
              } else {
                onCategory(category);
              }
            },
          ),
        ActionChip(
          key: const Key('add_custom_category'),
          avatar: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add your own'),
          onPressed: () => _addCategoryAndApply(context, ref),
        ),
      ],
    );
  }

  /// Names a category the built-in list does not cover — income tax, a premium,
  /// a fee — files this transaction under it, and keeps it in the picker for
  /// every later one.
  Future<void> _addCategoryAndApply(BuildContext context, WidgetRef ref) async {
    final atLimit = ref.read(customSpendCategoriesProvider).length >=
        CustomSpendCategory.maxPerUser;
    if (atLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You already have the maximum number of your own categories.',
          ),
        ),
      );
      return;
    }

    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _NewCategoryDialog(),
    );
    final trimmed = typed?.trim() ?? '';
    if (trimmed.isEmpty) return;

    final id = await ref
        .read(customSpendCategoriesProvider.notifier)
        .addFromUserText(trimmed);
    if (id == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That name has no letters or numbers to save.'),
          ),
        );
      }
      return;
    }
    onCategory(id);
  }

  bool _isSelected(String category) {
    final current = selected;
    if (current == null) return false;
    // An insurance sub-type highlights the parent chip.
    return current == category ||
        (category == SpendCategory.insurance &&
            current.startsWith('${SpendCategory.insurance}:'));
  }
}

class _SwipeReviewDone extends StatelessWidget {
  const _SwipeReviewDone({required this.resolved, required this.total});
  final int resolved;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: PaycheckColors.matchedSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: PaycheckColors.matched, size: 32),
        ),
        const SizedBox(height: 16),
        Text('All caught up', style: PaycheckType.title()),
        const SizedBox(height: 8),
        Text(
          resolved == total
              ? 'Categorized all $total transactions.'
              : 'Categorized $resolved of $total. The rest stay as Other for now.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _CategoryPie extends StatelessWidget {
  const _CategoryPie({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final entries = map.topCategories;
    if (entries.isEmpty) return const SizedBox.shrink();
    return _Card(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 118,
            child: CustomPaint(painter: _SpendPiePainter(entries)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.take(5).map((entry) {
                final share =
                    map.totalSpent == 0 ? 0 : entry.value / map.totalSpent;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${SpendCategory.label(entry.key)} ${(share * 100).round()}%',
                    style: PaycheckType.utility(),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendPiePainter extends CustomPainter {
  const _SpendPiePainter(this.entries);

  final List<MapEntry<String, int>> entries;
  static const colors = [
    PaycheckColors.contract,
    PaycheckColors.claim,
    PaycheckColors.matched,
    PaycheckColors.pending,
    Color(0xFF64748B),
    Color(0xFF7C3AED),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total <= 0) return;
    var start = -1.5708;
    final rect = Offset.zero & size;
    for (var index = 0; index < entries.length; index++) {
      final sweep = entries[index].value / total * 6.28319;
      canvas.drawArc(
        rect.deflate(8),
        start,
        sweep,
        true,
        Paint()..color = colors[index % colors.length],
      );
      start += sweep;
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * 0.22,
      Paint()..color = PaycheckColors.paper,
    );
  }

  @override
  bool shouldRepaint(covariant _SpendPiePainter oldDelegate) =>
      oldDelegate.entries != entries;
}

class _MonthlyTrend extends StatelessWidget {
  const _MonthlyTrend({required this.map});

  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final points = map.monthlyTrend;
    if (points.isEmpty) {
      return Text(
        'No monthly trend available.',
        style: PaycheckType.body(color: PaycheckColors.inkSoft),
      );
    }
    // Scale both series against the combined peak so spend and income share a
    // baseline and the comparison is honest.
    final max = points.fold<int>(
      1,
      (value, point) =>
          [value, point.spent, point.income].reduce((a, b) => a > b ? a : b),
    );
    final hasIncome = points.any((p) => p.income > 0);
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          SizedBox(
            height: 172,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                final spendH = (112 * point.spent / max).clamp(2, 112);
                final incomeH = (112 * point.income / max).clamp(0, 112);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          money0(point.spent),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          style: PaycheckType.utility(),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Bar(
                              height: spendH.toDouble(),
                              color: PaycheckColors.claim,
                            ),
                            if (hasIncome) ...[
                              const SizedBox(width: 4),
                              _Bar(
                                height: incomeH.toDouble(),
                                color: PaycheckColors.contract,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('MMM').format(point.month),
                          style: PaycheckType.utility(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          if (hasIncome) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: PaycheckColors.claim, label: 'Spend'),
                SizedBox(width: 16),
                _LegendDot(color: PaycheckColors.contract, label: 'Income'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});
  final double height;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: PaycheckType.utility()),
      ],
    );
  }
}

class _SavingsHero extends StatelessWidget {
  const _SavingsHero({required this.map, required this.period});
  final SpendMap map;
  final SpendScanPeriod period;
  @override
  Widget build(BuildContext context) {
    final unknownIncome = map.monthlyIncome <= 0;
    final overspending = map.isOverspending;
    final rate = (map.savingsRate * 100).round();
    final coaching = _coachingLine(map);

    // Colour + copy switch on the sign of the net so a shortfall reads as a
    // shortfall instead of a floored-to-zero "0 savings".
    final accent = unknownIncome
        ? PaycheckColors.inkSoft
        : overspending
            ? PaycheckColors.claim
            : PaycheckColors.matched;
    final softBg = unknownIncome
        ? PaycheckColors.paper
        : overspending
            ? PaycheckColors.claim.withValues(alpha: 0.08)
            : PaycheckColors.matchedSoft;
    final headline = unknownIncome
        ? 'MONTHLY BALANCE'
        : overspending
            ? 'MONTHLY OVERSPEND'
            : 'REALISTIC MONTHLY SAVINGS';
    final figure = unknownIncome ? '—' : money0(map.monthlyNet.abs());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: softBg,
        borderRadius: AppRadius.card,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: PaycheckType.utility(color: accent)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (overspending)
                Text('− ',
                    style: PaycheckType.display(color: PaycheckColors.claim)),
              Text(figure,
                  style: PaycheckType.display(color: PaycheckColors.ink)),
            ],
          ),
          if (!unknownIncome)
            Text(
              overspending
                  ? '${(map.monthlyWaste / map.monthlyIncome * 100).round()}% more than you earn'
                  : map.primaryIncomeIsManual
                      ? '$rate% of your entered income'
                      : map.incomeIsDetected
                          ? '$rate% of detected income'
                          : '$rate% of estimated income (from your payslip)',
              style: PaycheckType.utility(),
            ),
          if (!unknownIncome) ...[
            const SizedBox(height: 8),
            Text(
              'Based on ${period.windowPhrase} averages. Tap income or spend to edit.',
              style: PaycheckType.utility(color: PaycheckColors.inkSoft),
            ),
          ],
          if (map.netMixesSources) ...[
            const SizedBox(height: 8),
            Text(
              'Income is a payslip estimate, spend is from SMS.',
              style: PaycheckType.utility(color: PaycheckColors.inkSoft),
            ),
            const ArthDisclosure(
              label: 'Why this balance is approximate',
              icon: Icons.help_outline,
              detail:
                  'This figure mixes two sources. Rescan after payday so ARTH can detect your salary credit and give an exact number.',
            ),
          ],
          const SizedBox(height: 12),
          Text(coaching, style: PaycheckType.body()),
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.map});
  final SpendMap map;
  @override
  Widget build(BuildContext context) {
    final categories = map.topCategories;
    if (categories.isEmpty) {
      return Text('No spends detected yet.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft));
    }
    final max = categories.first.value;
    return Column(
      children: [
        for (final entry in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(_iconFor(entry.key),
                    size: 20, color: PaycheckColors.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(SpendCategory.label(entry.key),
                                style: PaycheckType.bodyStrong()),
                          ),
                          Text(money0(entry.value),
                              style: PaycheckType.bodyStrong()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : entry.value / max,
                          minHeight: 8,
                          backgroundColor: PaycheckColors.line,
                          color: PaycheckColors.claim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EditableStatTile extends StatelessWidget {
  const _EditableStatTile({
    required this.label,
    required this.caption,
    required this.value,
    required this.color,
    required this.onTap,
    this.edited = false,
  });

  final String label;
  final String caption;
  final String value;
  final Color color;
  final VoidCallback onTap;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PaycheckColors.paper,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(
              color:
                  edited ? color.withValues(alpha: 0.45) : PaycheckColors.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: PaycheckType.utility(color: color),
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 16, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Text(value, style: PaycheckType.title()),
              if (edited) ...[
                const SizedBox(height: 4),
                Text(
                  'Edited',
                  style: PaycheckType.utility(color: color),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                caption,
                style: PaycheckType.utility(color: PaycheckColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.map});
  final SpendMap map;

  @override
  Widget build(BuildContext context) {
    final projected = map.projectedMonthlySpend;
    final pace = map.spendPaceVsAverage;
    final overPace = pace > 0.05;
    final underPace = pace < -0.05;
    final pacePct = (pace.abs() * 100).round();
    final trends = map.categoryTrends.take(3).toList();

    final paceLine = overPace
        ? 'On pace to spend $pacePct% more than your usual month.'
        : underPace
            ? 'On pace to spend $pacePct% less than your usual month.'
            : 'On pace with your usual monthly spend.';
    final paceColor = overPace
        ? PaycheckColors.claim
        : underPace
            ? PaycheckColors.matched
            : PaycheckColors.inkSoft;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROJECTED THIS MONTH', style: PaycheckType.utility()),
          const SizedBox(height: 8),
          Text(money0(projected), style: PaycheckType.title()),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                overPace
                    ? Icons.trending_up
                    : underPace
                        ? Icons.trending_down
                        : Icons.trending_flat,
                size: 18,
                color: paceColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(paceLine,
                    style: PaycheckType.utility(color: paceColor)),
              ),
            ],
          ),
          if (trends.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('BIGGEST MOVERS', style: PaycheckType.utility()),
            const SizedBox(height: 8),
            for (final t in trends) _TrendRow(trend: t),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Scan a longer window (3–6 months) to unlock per-category trends.',
              style: PaycheckType.utility(color: PaycheckColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trend});
  final CategoryTrend trend;
  @override
  Widget build(BuildContext context) {
    final up = trend.isUp;
    final color = up ? PaycheckColors.claim : PaycheckColors.matched;
    final pct = (trend.changeRatio.abs() * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(_iconFor(trend.category),
              size: 18, color: PaycheckColors.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(SpendCategory.label(trend.category),
                style: PaycheckType.body()),
          ),
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text('$pct%', style: PaycheckType.bodyStrong(color: color)),
          const SizedBox(width: 8),
          Text(money0(trend.lastMonth),
              style: PaycheckType.utility(color: PaycheckColors.inkSoft)),
        ],
      ),
    );
  }
}

class _TransactionList extends StatefulWidget {
  const _TransactionList({required this.map});
  final SpendMap map;

  @override
  State<_TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends State<_TransactionList> {
  static const _initialCount = 12;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Most recent first. Carries each transaction's index in `map.txns` so a
    // row can be re-filed — the notifier addresses transactions by that index,
    // which display order would otherwise lose.
    final txns = [...widget.map.txns.indexed]
      ..sort((a, b) => b.$2.date.compareTo(a.$2.date));
    if (txns.isEmpty) {
      return Text('No transactions detected yet.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft));
    }
    final shown = _expanded ? txns : txns.take(_initialCount).toList();
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          for (final entry in shown)
            _TransactionRow(index: entry.$1, txn: entry.$2),
          if (txns.length > _initialCount)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded
                  ? 'Show less'
                  : 'Show all ${txns.length} transactions'),
            ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.index, required this.txn});

  /// Index of this transaction in `SpendMap.txns`, not in display order.
  final int index;
  final FinanceTxn txn;

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.direction == TxnDirection.debit;
    final title = txn.merchant?.trim().isNotEmpty == true
        ? txn.merchant!
        : (txn.sender ?? 'Unknown');
    return InkWell(
      onTap: () => _showTxnDetail(context, txn, index),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: PaycheckColors.canvas,
                borderRadius: AppRadius.control,
              ),
              child: Icon(
                isDebit ? _iconFor(txn.category) : Icons.south_west,
                size: 18,
                color:
                    isDebit ? PaycheckColors.inkSoft : PaycheckColors.matched,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PaycheckType.bodyStrong(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('d MMM, h:mm a').format(txn.date)} · '
                    '${txn.sender ?? 'unknown'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isDebit ? '−' : '+'}${money0(txn.amount)}',
                  style: PaycheckType.bodyStrong(
                    color:
                        isDebit ? PaycheckColors.ink : PaycheckColors.matched,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDebit
                      ? SpendCategory.label(txn.category)
                      : (txn.isSalary ? 'Salary' : 'Credit'),
                  style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showTxnDetail(BuildContext context, FinanceTxn txn, int index) {
  final isDebit = txn.direction == TxnDirection.debit;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    // Named so the outer context stays reachable: the category picker is opened
    // from the page, after this sheet has been popped.
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${isDebit ? '−' : '+'}${money0(txn.amount)}',
                    style: PaycheckType.display(
                      color:
                          isDebit ? PaycheckColors.ink : PaycheckColors.matched,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _DetailRow(
                label: 'When',
                value: DateFormat('EEE, d MMM yyyy · h:mm a').format(txn.date)),
            _DetailRow(label: 'Contact', value: txn.sender ?? 'Unknown'),
            if (txn.merchant?.trim().isNotEmpty == true)
              _DetailRow(label: 'Merchant', value: txn.merchant!),
            _DetailRow(
              label: 'Category',
              value: isDebit
                  ? SpendCategory.label(txn.category)
                  : (txn.isSalary ? 'Salary' : 'Credit'),
            ),
            // Filing was only reachable from the unclear-transaction review,
            // which surfaces `other` transactions — a wrong category on any
            // other transaction could not be corrected at all.
            if (isDebit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showCategoryPicker(context, txn, index);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Change category'),
                ),
              ),
            if (txn.bodyPreview?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text('ORIGINAL SMS', style: PaycheckType.utility()),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PaycheckColors.canvas,
                  borderRadius: AppRadius.control,
                  border: Border.all(color: PaycheckColors.line),
                ),
                child: Text(txn.bodyPreview!, style: PaycheckType.body()),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openInMessages(sheetContext, txn),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open in Messages app'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Re-files one transaction into a category the user picks. The choice is
/// remembered per merchant, so the same payee is filed automatically on later
/// scans instead of needing the same correction again.
Future<void> _showCategoryPicker(
  BuildContext context,
  FinanceTxn txn,
  int index,
) {
  final merchant = txn.merchant?.trim();
  final remembersMerchant =
      MerchantCategoryRules.keyFor(merchant) != null && merchant != null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Consumer(
          builder: (_, ref, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File this transaction', style: PaycheckType.heading()),
              const SizedBox(height: 4),
              Text(
                remembersMerchant
                    ? 'Future payments to $merchant will use this category.'
                    : 'This transaction only — there is no payee name to '
                        'remember it against.',
                style: PaycheckType.utility(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 16),
              _CategoryChips(
                selected: txn.category,
                onCategory: (category) {
                  ref
                      .read(spendMapProvider.notifier)
                      .recategorize(index, category);
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Best-effort jump to the phone's SMS app. Opening one exact message by id is
/// not portable across Android OEMs, so we open the messaging app scoped to the
/// sender (the in-app "Original SMS" text above is the reliable path). Shows a
/// snackbar if no SMS app can handle the intent.
Future<void> _openInMessages(BuildContext context, FinanceTxn txn) async {
  final sender = txn.sender;
  final uri = Uri(scheme: 'sms', path: sender ?? '');
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content:
            Text('No messaging app available. The SMS text is shown above.'),
      ));
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Could not open the messaging app.'),
    ));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: PaycheckType.utility(color: PaycheckColors.inkSoft)),
          ),
          Expanded(child: Text(value, style: PaycheckType.body())),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.line),
      ),
      child: child,
    );
  }
}

IconData _iconFor(String category) {
  // Covers the insurance sub-types ("insurance:car") with the parent icon.
  if (category.startsWith(SpendCategory.insurance)) {
    return Icons.shield_outlined;
  }
  switch (category) {
    case SpendCategory.food:
      return Icons.restaurant_outlined;
    case SpendCategory.groceries:
      return Icons.local_grocery_store_outlined;
    case SpendCategory.transport:
      return Icons.directions_car_outlined;
    case SpendCategory.shopping:
      return Icons.shopping_bag_outlined;
    case SpendCategory.entertainment:
      return Icons.movie_outlined;
    case SpendCategory.bills:
      return Icons.receipt_outlined;
    case SpendCategory.health:
      return Icons.medical_services_outlined;
    case SpendCategory.rent:
      return Icons.home_outlined;
    case SpendCategory.investment:
      return Icons.trending_up_outlined;
    case SpendCategory.cash:
      return Icons.atm_outlined;
    case SpendCategory.travel:
      return Icons.flight_takeoff_outlined;
    case SpendCategory.education:
      return Icons.school_outlined;
    case SpendCategory.loan:
      return Icons.account_balance_outlined;
    case SpendCategory.fees:
      return Icons.percent_outlined;
    case SpendCategory.subscriptions:
      return Icons.autorenew_outlined;
    case SpendCategory.transfer:
      return Icons.send_outlined;
    case SpendCategory.pets:
      return Icons.pets_outlined;
    case SpendCategory.gifts:
      return Icons.card_giftcard_outlined;
    case SpendCategory.personalCare:
      return Icons.spa_outlined;
    case String() when SpendCategory.isCustom(category):
      return Icons.sell_outlined;
    default:
      return Icons.category_outlined;
  }
}

String _coachingLine(SpendMap map) {
  if (map.monthlyIncome <= 0) {
    return 'No salary credit detected in your SMS yet. Add a salary account or '
        'rescan after payday to see realistic savings.';
  }
  final rate = map.savingsRate;
  final top = map.topCategories.isNotEmpty ? map.topCategories.first : null;
  final topLine = top == null
      ? ''
      : ' Your biggest lever is ${SpendCategory.label(top.key).toLowerCase()} '
          '(${money0(top.value)}).';
  if (rate >= 0.3) {
    return 'Strong — you keep ${(rate * 100).round()}% of income. '
        'Automate ${money0(map.realisticMonthlySavings)} on payday toward your goal.$topLine';
  }
  if (rate > 0) {
    return 'You currently save ${(rate * 100).round()}%. Trimming one category could '
        'lift this.$topLine';
  }
  return 'Spending matches or exceeds detected income. Review your largest '
      'categories before committing to a goal.$topLine';
}
