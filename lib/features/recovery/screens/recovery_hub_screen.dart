import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../theme/paycheck_theme.dart';
import '../models/recovery_models.dart';
import '../providers/recovery_provider.dart';

class RecoveryHubScreen extends ConsumerWidget {
  const RecoveryHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Money recovery', style: PaycheckType.heading()),
      ),
      body: recovery.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(recoveryProvider),
            child: const Text('Recovery data could not load. Try again.'),
          ),
        ),
        data: (state) => _RecoveryBody(state: state),
      ),
    );
  }
}

class _RecoveryBody extends ConsumerWidget {
  const _RecoveryBody({required this.state});

  final RecoveryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeClaims = state.claimCases
        .where(
          (claim) =>
              claim.status != ClaimCaseStatus.paid &&
              claim.status != ClaimCaseStatus.closed,
        )
        .toList(growable: false);
    final recoverable = activeClaims.fold<int>(
      0,
      (sum, claim) => sum + claim.amount,
    );
    final upcomingDeadlines = state.benefits
        .where(
          (benefit) =>
              benefit.deadline != null &&
              !benefit.deadline!.isBefore(DateTime.now()),
        )
        .toList(growable: false)
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text('RECOVERY LEDGER', style: PaycheckType.sectionLabel()),
          const SizedBox(height: 8),
          Text(
            _money(recoverable),
            style: PaycheckType.display(color: PaycheckColors.matched),
          ),
          Text(
            activeClaims.isEmpty
                ? 'No open claim cases'
                : '${activeClaims.length} open ${activeClaims.length == 1 ? 'case' : 'cases'}',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          if (state.checklists.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PaydayCard(checklist: state.checklists.first),
          ],
          if (upcomingDeadlines.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DeadlineNudge(benefit: upcomingDeadlines.first),
          ],
          const SizedBox(height: 26),
          const _SectionTitle(
            title: 'Claim cases',
            detail: 'Review, prepare, submit, then mark paid.',
          ),
          const SizedBox(height: 10),
          if (state.claimCases.isEmpty)
            const _EmptyCard(
              text:
                  'No mismatch or claimable benefit found in confirmed pay data.',
            )
          else
            ...state.claimCases.map(
              (claim) => _ClaimRow(
                claim: claim,
                onOpen: () => context.push(
                  '/recovery/claim/${Uri.encodeComponent(claim.id)}',
                ),
                onStatus: (status) => ref
                    .read(recoveryProvider.notifier)
                    .updateClaim(claim.id, status: status),
              ),
            ),
          const SizedBox(height: 26),
          const _SectionTitle(
            title: 'Benefits',
            detail: 'Confirmed caps only. Unknown policy stays unknown.',
          ),
          const SizedBox(height: 10),
          if (state.benefits.isEmpty)
            const _EmptyCard(
              text: 'Add an offer letter to build a benefit ledger.',
            )
          else
            ...state.benefits.map(
              (benefit) => _BenefitCard(
                benefit,
                onEdit: () => _editBenefit(context, ref, benefit),
              ),
            ),
          const SizedBox(height: 26),
          const _SectionTitle(
            title: 'Monthly history',
            detail: 'New snapshots appear after a payslip is confirmed.',
          ),
          const SizedBox(height: 10),
          if (state.history.isEmpty)
            const _EmptyCard(text: 'No confirmed monthly snapshot yet.')
          else
            ...state.history.asMap().entries.map(
                  (entry) => _HistoryCard(
                    entry.value,
                    previous: entry.key + 1 < state.history.length
                        ? state.history[entry.key + 1]
                        : null,
                  ),
                ),
          const SizedBox(height: 26),
          _PlaybookCard(state: state),
        ],
      ),
    );
  }

  Future<void> _editBenefit(
    BuildContext context,
    WidgetRef ref,
    BenefitLedgerEntry benefit,
  ) async {
    final capController = TextEditingController(
      text: benefit.annualCap?.toString() ?? '',
    );
    var resetMonth = benefit.resetMonth ?? 4;
    var deadline = benefit.deadline ?? DateTime(DateTime.now().year, 12, 31);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Benefit policy', style: PaycheckType.title()),
              const SizedBox(height: 4),
              Text(
                benefit.label,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: capController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Annual cap',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: resetMonth,
                decoration: const InputDecoration(
                  labelText: 'Reset month',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var month = 1; month <= 12; month++)
                    DropdownMenuItem(
                      value: month,
                      child: Text(
                        DateFormat('MMMM').format(DateTime(2026, month)),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => resetMonth = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Claim deadline', style: PaycheckType.bodyStrong()),
                subtitle: Text(
                  DateFormat('d MMMM yyyy').format(deadline),
                  style: PaycheckType.body(),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: deadline,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) {
                    setSheetState(() => deadline = picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final cap =
                        int.tryParse(capController.text.replaceAll(',', ''));
                    if (cap == null || cap <= 0) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('Save policy details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final cap = int.tryParse(capController.text.replaceAll(',', ''));
    capController.dispose();
    if (saved != true || cap == null || cap <= 0) return;
    await ref.read(recoveryProvider.notifier).updateBenefit(
          benefit.id,
          annualCap: cap,
          resetMonth: resetMonth,
          deadline: deadline,
        );
  }
}

class _DeadlineNudge extends StatelessWidget {
  const _DeadlineNudge({required this.benefit});

  final BenefitLedgerEntry benefit;

  @override
  Widget build(BuildContext context) {
    final days = benefit.deadline!.difference(DateTime.now()).inDays + 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PaycheckColors.claimSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_available_outlined,
            color: PaycheckColors.claim,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CLAIM DEADLINE', style: PaycheckType.utility()),
                Text(benefit.label, style: PaycheckType.bodyStrong()),
              ],
            ),
          ),
          Text(
            days <= 1 ? 'Today' : '$days days',
            style: PaycheckType.money(color: PaycheckColors.claim),
          ),
        ],
      ),
    );
  }
}

class _PaydayCard extends ConsumerWidget {
  const _PaydayCard({required this.checklist});

  final PaydayChecklist checklist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            checklist.complete ? 'MONTH CLOSED' : 'PAYDAY CHECK',
            style: PaycheckType.sectionLabel(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            _month(checklist.monthKey),
            style: PaycheckType.title(color: Colors.white),
          ),
          const SizedBox(height: 12),
          _CheckLine(
              label: 'Salary credit found', value: checklist.creditFound),
          _CheckLine(
            label: 'Payslip checked',
            value: checklist.payslipChecked,
            onTap: () => ref.read(recoveryProvider.notifier).setChecklistItem(
                  checklist.monthKey,
                  payslipChecked: !checklist.payslipChecked,
                ),
          ),
          _CheckLine(
            label: 'Claim items reviewed',
            value: checklist.claimItemsReviewed,
            onTap: () => ref.read(recoveryProvider.notifier).setChecklistItem(
                  checklist.monthKey,
                  claimItemsReviewed: !checklist.claimItemsReviewed,
                ),
          ),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: value ? PaycheckColors.matched : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: PaycheckType.body(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({
    required this.claim,
    required this.onOpen,
    required this.onStatus,
  });

  final ClaimCase claim;
  final VoidCallback onOpen;
  final ValueChanged<ClaimCaseStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            onTap: onOpen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            leading: Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: _statusColor(claim.status),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(claim.label, style: PaycheckType.bodyStrong()),
            subtitle: Text(
              claim.status.name.toUpperCase(),
              style: PaycheckType.utility(color: _statusColor(claim.status)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_money(claim.amount), style: PaycheckType.money()),
                PopupMenuButton<ClaimCaseStatus>(
                  onSelected: onStatus,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: ClaimCaseStatus.submitted,
                      child: Text('Mark submitted'),
                    ),
                    PopupMenuItem(
                      value: ClaimCaseStatus.paid,
                      child: Text('Mark paid'),
                    ),
                    PopupMenuItem(
                      value: ClaimCaseStatus.closed,
                      child: Text('Close case'),
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
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard(this.benefit, {required this.onEdit});

  final BenefitLedgerEntry benefit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PaycheckColors.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                        Text(benefit.label, style: PaycheckType.bodyStrong()),
                  ),
                  Text(
                    benefit.remaining == null
                        ? 'Add cap'
                        : '${_money(benefit.remaining!)} left',
                    style: PaycheckType.money(
                      color: benefit.remaining == null
                          ? PaycheckColors.contract
                          : PaycheckColors.matched,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 16),
                ],
              ),
              const SizedBox(height: 5),
              Text(benefit.source, style: PaycheckType.utility()),
              if (benefit.deadline != null || benefit.resetMonth != null) ...[
                const SizedBox(height: 5),
                Text(
                  [
                    if (benefit.deadline != null)
                      'Claim by ${DateFormat('d MMM yyyy').format(benefit.deadline!)}',
                    if (benefit.resetMonth != null)
                      'Resets in ${DateFormat('MMMM').format(DateTime(2026, benefit.resetMonth!))}',
                  ].join(' · '),
                  style: PaycheckType.utility(color: PaycheckColors.claim),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard(this.snapshot, {required this.previous});

  final ReconciliationSnapshot snapshot;
  final ReconciliationSnapshot? previous;

  @override
  Widget build(BuildContext context) {
    final deltaColor =
        snapshot.delta < 0 ? PaycheckColors.claim : PaycheckColors.matched;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(snapshot.payPeriod, style: PaycheckType.bodyStrong()),
            subtitle: Text(
              '${_money(snapshot.netPaid)} net · ${_money(snapshot.salaryCredit)} bank credit',
              style: PaycheckType.utility(),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _HistoryValue('Promised', snapshot.promised),
                  ),
                  Expanded(
                    child: _HistoryValue('Gross paid', snapshot.grossPaid),
                  ),
                  Expanded(
                    child: _HistoryValue(
                      'Difference',
                      snapshot.delta,
                      color: deltaColor,
                      signed: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...snapshot.itemAmounts.entries.map((entry) {
                final oldAmount = previous?.itemAmounts[entry.key];
                final change =
                    oldAmount == null ? null : entry.value - oldAmount;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          snapshot.itemLabels[entry.key] ?? entry.key,
                          style: PaycheckType.body(),
                        ),
                      ),
                      if (change != null && change != 0) ...[
                        Text(
                          '${change > 0 ? '+' : ''}${_money(change)}',
                          style: PaycheckType.utility(
                            color: change < 0
                                ? PaycheckColors.claim
                                : PaycheckColors.matched,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(_money(entry.value), style: PaycheckType.money()),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryValue extends StatelessWidget {
  const _HistoryValue(
    this.label,
    this.value, {
    this.color = PaycheckColors.ink,
    this.signed = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final prefix = signed && value > 0 ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PaycheckType.utility()),
        const SizedBox(height: 2),
        Text('$prefix${_money(value)}',
            style: PaycheckType.money(color: color)),
      ],
    );
  }
}

class _PlaybookCard extends StatelessWidget {
  const _PlaybookCard({required this.state});

  final RecoveryState state;

  @override
  Widget build(BuildContext context) {
    final playbook = state.playbook;
    final named = playbook != null && playbook.key != 'generic';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.contractSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EMPLOYER PLAYBOOK', style: PaycheckType.sectionLabel()),
          const SizedBox(height: 5),
          Text(
            named ? playbook.name : 'Generic rules only',
            style: PaycheckType.heading(),
          ),
          const SizedBox(height: 4),
          Text(
            named
                ? 'Employer matched. No policy number is used unless its source is verified.'
                : 'Add your employer. ARTH will still use confirmed offer and payslip terms.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 8),
          Text(
            'Dataset ${state.datasetVersion}',
            style: PaycheckType.utility(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PaycheckType.heading()),
        const SizedBox(height: 3),
        Text(detail, style: PaycheckType.body(color: PaycheckColors.inkSoft)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        border: Border.all(color: PaycheckColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: PaycheckType.body()),
    );
  }
}

String _money(int value) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(value);

String _month(String key) {
  final parsed = DateTime.tryParse('$key-01');
  return parsed == null ? key : DateFormat('MMMM yyyy').format(parsed);
}

Color _statusColor(ClaimCaseStatus status) => switch (status) {
      ClaimCaseStatus.review => PaycheckColors.claim,
      ClaimCaseStatus.prepared => PaycheckColors.contract,
      ClaimCaseStatus.submitted => PaycheckColors.pending,
      ClaimCaseStatus.paid => PaycheckColors.matched,
      ClaimCaseStatus.closed => PaycheckColors.inkSoft,
    };
