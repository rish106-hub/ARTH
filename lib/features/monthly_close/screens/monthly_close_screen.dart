import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../models/monthly_close_models.dart';
import '../providers/monthly_close_provider.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

String _shortDate(DateTime date) => DateFormat('d MMM yyyy').format(date);

class MonthlyCloseScreen extends ConsumerWidget {
  const MonthlyCloseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(monthlyCloseProvider);
    final snapshot = ref.watch(monthlyCloseSnapshotProvider);
    final completed = record.completedSteps.length;

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        title: Text('Monthly close', style: PaycheckType.heading()),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              snapshot.periodLabel.toUpperCase(),
              style: PaycheckType.sectionLabel(),
            ),
            const SizedBox(height: 8),
            Text('Your 5-minute pay close', style: PaycheckType.title()),
            const SizedBox(height: 8),
            Text(
              'Confirm what arrived. Check new bills. Mark claims reviewed.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 20),
            _CloseDocket(
              record: record,
              snapshot: snapshot,
              onChanged: (step, value) =>
                  ref.read(monthlyCloseProvider.notifier).setStep(step, value),
            ),
            const SizedBox(height: 20),
            _EvidenceLedger(health: snapshot.evidenceHealth),
            const SizedBox(height: 20),
            _AuditLedger(audits: snapshot.figureAudits),
            if (snapshot.cohort.canShowComparison) ...[
              const SizedBox(height: 20),
              _CohortCard(cohort: snapshot.cohort),
            ],
            if (!record.isComplete) ...[
              const SizedBox(height: 16),
              Text(
                '$completed of ${MonthlyCloseStep.values.length} checks done',
                textAlign: TextAlign.center,
                style: PaycheckType.utility(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MonthlyCloseEntryCard extends StatelessWidget {
  const MonthlyCloseEntryCard({
    super.key,
    required this.record,
    required this.snapshot,
    required this.onTap,
  });

  final MonthlyCloseRecord record;
  final MonthlyCloseSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final complete = record.isComplete;
    final count = record.completedSteps.length;
    return Material(
      color: complete ? PaycheckColors.matchedSoft : PaycheckColors.paper,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: complete ? PaycheckColors.matched : PaycheckColors.contract,
        ),
        borderRadius: AppRadius.control,
      ),
      child: InkWell(
        key: const Key('open_monthly_close'),
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: complete
                      ? PaycheckColors.matched
                      : PaycheckColors.contractSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  complete
                      ? Icons.task_alt_rounded
                      : Icons.receipt_long_outlined,
                  color: complete ? Colors.white : PaycheckColors.contract,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete
                          ? '${snapshot.periodLabel} closed'
                          : 'Close ${snapshot.periodLabel}',
                      style: PaycheckType.bodyStrong(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      complete
                          ? 'Evidence and claims checked'
                          : '$count of 3 checks done · about 5 minutes',
                      style: PaycheckType.utility(),
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

class _CloseDocket extends StatelessWidget {
  const _CloseDocket({
    required this.record,
    required this.snapshot,
    required this.onChanged,
  });

  final MonthlyCloseRecord record;
  final MonthlyCloseSnapshot snapshot;
  final void Function(MonthlyCloseStep step, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        border: Border.all(color: PaycheckColors.ink),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Text('PAYDAY DOCKET', style: PaycheckType.sectionLabel()),
                const Spacer(),
                Text(
                  '${record.completedSteps.length}/3',
                  style: PaycheckType.money(size: 14),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: PaycheckColors.ink),
          _CloseStepRow(
            number: '01',
            title: 'Confirm salary credit',
            detail: switch (snapshot.creditStatus) {
              MonthlyCloseCreditStatus.confirmed =>
                '${_money(snapshot.creditAmount)} credited to your account',
              MonthlyCloseCreditStatus.awaitingCredit =>
                'No salary credit seen yet',
              MonthlyCloseCreditStatus.smsNotConnected =>
                'Connect salary SMS to confirm the credit',
              MonthlyCloseCreditStatus.demoData =>
                'Demo figures cannot confirm a credit',
            },
            checked: record.completedSteps.contains(MonthlyCloseStep.credit),
            onChanged: (value) => onChanged(MonthlyCloseStep.credit, value),
            enabled: snapshot.creditConfirmed,
          ),
          _CloseStepRow(
            number: '02',
            title: 'Check new bills',
            detail: snapshot.evidenceHealth.pendingReceiptCount == 0
                ? 'No receipts waiting'
                : '${snapshot.evidenceHealth.pendingReceiptCount} receipts waiting',
            actionLabel: 'Evidence',
            onAction: () => context.push('/paycheck/evidence'),
            checked: record.completedSteps.contains(MonthlyCloseStep.bills),
            onChanged: (value) => onChanged(MonthlyCloseStep.bills, value),
          ),
          _CloseStepRow(
            number: '03',
            title: 'Review claims',
            detail: snapshot.openClaimCount == 0
                ? 'No open claims'
                : '${snapshot.openClaimCount} open',
            actionLabel: snapshot.openClaimCount == 0 ? null : 'Review',
            onAction: snapshot.openClaimCount == 0
                ? null
                : () => context.push('/recovery'),
            checked: record.completedSteps.contains(MonthlyCloseStep.claims),
            onChanged: (value) => onChanged(MonthlyCloseStep.claims, value),
            last: true,
          ),
          if (record.isComplete) ...[
            const Divider(height: 1, color: PaycheckColors.ink),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: PaycheckColors.matched,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CLOSED ${record.completedAt == null ? '' : _shortDate(record.completedAt!).toUpperCase()}',
                      style: PaycheckType.sectionLabel(
                        color: PaycheckColors.matched,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloseStepRow extends StatelessWidget {
  const _CloseStepRow({
    required this.number,
    required this.title,
    required this.detail,
    required this.checked,
    required this.onChanged,
    this.actionLabel,
    this.onAction,
    this.last = false,
    this.enabled = true,
  });

  final String number;
  final String title;
  final String detail;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool last;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Text(number, style: PaycheckType.utility()),
          const SizedBox(width: 8),
          Checkbox(
            value: checked,
            onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            activeColor: PaycheckColors.matched,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PaycheckType.bodyStrong(
                    color:
                        enabled ? PaycheckColors.ink : PaycheckColors.inkSoft,
                  ),
                ),
                Text(detail, style: PaycheckType.utility()),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _EvidenceLedger extends StatelessWidget {
  const _EvidenceLedger({required this.health});

  final EvidenceHealth health;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Evidence health', style: PaycheckType.heading()),
            ),
            Text(
              '${health.readyCount}/${health.totalCount} ready',
              style: PaycheckType.utility(
                color: health.readyCount == health.totalCount
                    ? PaycheckColors.matched
                    : PaycheckColors.pending,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: PaycheckColors.paper,
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              for (var index = 0; index < health.items.length; index++)
                _LedgerRow(
                  item: health.items[index],
                  last: index == health.items.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item, required this.last});

  final EvidenceHealthItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Icon(
            item.ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 19,
            color: item.ready ? PaycheckColors.matched : PaycheckColors.pending,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item.label, style: PaycheckType.bodyStrong())),
          Text(item.detail, style: PaycheckType.utility()),
        ],
      ),
    );
  }
}

class _AuditLedger extends StatelessWidget {
  const _AuditLedger({required this.audits});

  final List<FigureAudit> audits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Figure audit trail', style: PaycheckType.heading()),
        const SizedBox(height: 4),
        Text(
          'Tap a rupee figure to see where it came from.',
          style: PaycheckType.utility(),
        ),
        const SizedBox(height: 8),
        if (audits.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: PaycheckColors.paper,
            child: Text(
              'Connect a payslip, salary SMS, or CTC first.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: PaycheckColors.paper,
              border: Border.all(color: PaycheckColors.line),
              borderRadius: AppRadius.card,
            ),
            child: Column(
              children: [
                for (var index = 0; index < audits.length; index++)
                  InkWell(
                    onTap: () => showFigureAuditSheet(
                      context,
                      audits[index],
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: index == audits.length - 1
                            ? null
                            : const Border(
                                bottom: BorderSide(color: PaycheckColors.line),
                              ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              audits[index].label,
                              style: PaycheckType.body(),
                            ),
                          ),
                          Text(
                            _money(audits[index].amount),
                            style: PaycheckType.money(),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: PaycheckColors.inkSoft,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CohortCard extends StatelessWidget {
  const _CohortCard({required this.cohort});

  final CohortBenchmark cohort;

  @override
  Widget build(BuildContext context) {
    final title = 'Similar users spend ${cohort.averageRentPercent}% on rent';
    final detail =
        '${cohort.sampleSize} anonymous users in ${cohort.city}, ${cohort.ctcBandLabel}.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: PaycheckColors.surfaceMuted,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.groups_outlined,
            color: PaycheckColors.matched,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyStrong()),
                const SizedBox(height: 4),
                Text(detail, style: PaycheckType.utility()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showFigureAuditSheet(
  BuildContext context,
  FigureAudit audit,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PaycheckColors.paper,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(audit.label, style: PaycheckType.heading()),
            const SizedBox(height: 4),
            Text(_money(audit.amount), style: PaycheckType.displaySmall()),
            const SizedBox(height: 16),
            Text(
              audit.editedByUser ? 'YOUR EDIT' : 'SOURCE',
              style: PaycheckType.sectionLabel(),
            ),
            const SizedBox(height: 4),
            Text(audit.source, style: PaycheckType.bodyStrong()),
            const SizedBox(height: 4),
            Text(
              audit.detail,
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            if (audit.confirmedAt != null) ...[
              const SizedBox(height: 16),
              Text(
                '${audit.editedByUser ? 'Edited' : 'Confirmed'} ${_shortDate(audit.confirmedAt!)}',
                style: PaycheckType.utility(
                  color: audit.editedByUser
                      ? PaycheckColors.pending
                      : PaycheckColors.matched,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
