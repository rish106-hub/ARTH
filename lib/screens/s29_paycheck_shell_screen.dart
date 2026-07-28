import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/paycheck.dart';
import '../models/tax_document.dart';
import '../features/money_signals/providers/money_signal_provider.dart';
import '../models/money_signal_models.dart';
import '../features/monthly_close/models/monthly_close_models.dart';
import '../features/monthly_close/providers/monthly_close_provider.dart';
import '../features/monthly_close/screens/monthly_close_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/paycheck_override_provider.dart';
import '../providers/paycheck_provider.dart';
import '../providers/spend_map_adjustments_provider.dart';
import '../providers/tax_document_provider.dart';
import '../services/on_device_document_ocr_service.dart';
import '../services/server_api_service.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_brand_mark.dart';
import 's31_profile_screens.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

class PaycheckShellScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final bool exploreMode;

  const PaycheckShellScreen({
    super.key,
    this.initialIndex = 0,
    this.exploreMode = false,
  });

  @override
  ConsumerState<PaycheckShellScreen> createState() =>
      _PaycheckShellScreenState();
}

class _PaycheckShellScreenState extends ConsumerState<PaycheckShellScreen> {
  late int _index;
  late final PaycheckNotifier _paycheckNotifier;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 3);
    _paycheckNotifier = ref.read(paycheckProvider.notifier);
    if (widget.exploreMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _paycheckNotifier.useSampleData();
      });
    }
  }

  @override
  void dispose() {
    if (widget.exploreMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paycheckNotifier.closeSampleData();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paycheck = ref.watch(paycheckProvider);
    final pages = [
      _PaycheckHome(
        paycheck: paycheck,
        onOpenEvidence: () => setState(() => _index = 1),
        onOpenSettings: () => setState(() => _index = 3),
      ),
      _InboxView(
        paycheck: paycheck,
        exploreMode: widget.exploreMode,
        onPayslipApplied: () => setState(() => _index = 0),
      ),
      _TaxOverviewView(paycheck: paycheck),
      widget.exploreMode
          ? const _ExploreYouView()
          : _YouView(paycheck: paycheck),
    ];

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.exploreMode)
            Material(
              color: PaycheckColors.contractSoft,
              child: InkWell(
                onTap: () => context.go('/auth'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: PaycheckColors.contract,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'You are exploring sample data',
                          style: PaycheckType.utility(
                            color: PaycheckColors.contract,
                          ),
                        ),
                      ),
                      Text(
                        'SIGN UP',
                        style: PaycheckType.utility(
                          color: PaycheckColors.contract,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _PaycheckNav(
            selectedIndex: _index,
            onSelected: (value) => setState(() => _index = value),
          ),
        ],
      ),
    );
  }
}

class _ExploreYouView extends StatelessWidget {
  const _ExploreYouView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ArthBrandMark(size: 30),
            const Spacer(),
            const Icon(
              Icons.account_circle_outlined,
              size: 58,
              color: PaycheckColors.contract,
            ),
            const SizedBox(height: 20),
            Text('Make this workspace yours.', style: PaycheckType.title()),
            const SizedBox(height: 12),
            Text(
              'Sign up to add your offer letter, save evidence and keep every account separate.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: () => context.go('/auth'),
                style: FilledButton.styleFrom(
                  backgroundColor: PaycheckColors.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  'Sign up',
                  style: PaycheckType.bodyStrong(color: Colors.white),
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/auth?mode=sign-in'),
              child: Text('Already have an account? Sign in',
                  style: PaycheckType.bodyStrong()),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _PaycheckHome extends ConsumerWidget {
  final PaycheckState paycheck;
  final VoidCallback onOpenEvidence;
  final VoidCallback onOpenSettings;

  const _PaycheckHome({
    required this.paycheck,
    required this.onOpenEvidence,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionItems = paycheck.items
        .where(
          (item) =>
              item.status == PaycheckItemStatus.claimable ||
              item.status == PaycheckItemStatus.review,
        )
        .toList(growable: false);
    final hasPayslip = paycheck.grossReceived > 0 ||
        paycheck.netCredited > 0 ||
        paycheck.salarySmsConnected;
    final income = ref.watch(incomeSignalProvider);
    final closeRecord = ref.watch(monthlyCloseProvider);
    final closeSnapshot = ref.watch(monthlyCloseSnapshotProvider);
    FigureAudit? auditFor(String id) =>
        closeSnapshot.figureAudits.where((audit) => audit.id == id).firstOrNull;
    void openAudit(String id) {
      final audit = auditFor(id);
      if (audit != null) showFigureAuditSheet(context, audit);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              sample: paycheck.usingSampleData,
              onOpenSettings: onOpenSettings,
            ),
            const SizedBox(height: 24),
            _IncomeSourceStrip(
              income: income,
              onEdit: () => _editPlanningIncome(context, ref, income),
              onAudit: () => openAudit('planning-income'),
            ),
            const SizedBox(height: 20),
            if (!hasPayslip)
              _EmptyPaycheck(
                offerLetterAdded: paycheck.offerLetterAdded,
                onAddPayslip: onOpenEvidence,
              )
            else ...[
              Text(
                'Your ${paycheck.payPeriod} pay is ready',
                style: PaycheckType.title(),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '${_money(paycheck.netCredited)} net pay',
                button: true,
                child: InkWell(
                  onTap: () => openAudit('net-pay'),
                  child: Text(
                    _money(paycheck.netCredited),
                    key: const Key('paycheck_claimable_amount'),
                    style: PaycheckType.display(color: PaycheckColors.matched),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                paycheck.salarySmsConnected && paycheck.grossReceived <= 0
                    ? 'Net pay from salary SMS'
                    : 'Net pay',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              if (paycheck.salarySmsConnected && paycheck.grossReceived > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Salary SMS credit ${_money(paycheck.salarySmsCredited)}',
                    style: PaycheckType.utility(color: PaycheckColors.inkSoft),
                  ),
                ),
              const SizedBox(height: 20),
              _ComparisonStrip(
                paycheck: paycheck,
                onAudit: openAudit,
              ),
              const SizedBox(height: 12),
              MonthlyCloseEntryCard(
                record: closeRecord,
                snapshot: closeSnapshot,
                onTap: () => context.push('/monthly-close'),
              ),
              const SizedBox(height: 12),
              if (actionItems.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('review_paycheck_differences'),
                    onPressed: () =>
                        _openClaimSheet(context, ref, actionItems.first),
                    style: FilledButton.styleFrom(
                      backgroundColor: PaycheckColors.matched,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 20),
                    label: Text(
                      'Review ${actionItems.length} ${actionItems.length == 1 ? 'item' : 'items'}',
                      style: PaycheckType.bodyStrong(color: Colors.white),
                    ),
                  ),
                )
              else
                const _MatchedPaycheckStatus(),
              const SizedBox(height: 24),
              _PaycheckBreakdown(paycheck: paycheck),
              if (actionItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionHeading(
                  title: 'Needs your review',
                  count: actionItems.length,
                ),
                const SizedBox(height: 10),
                ...actionItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReviewRow(
                      item: item,
                      prepared: paycheck.preparedClaims.contains(item.id),
                      onTap: () => _openClaimSheet(context, ref, item),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _EvidenceStatus(
                paycheck: paycheck,
                onOpenEvidence: onOpenEvidence,
              ),
              const SizedBox(height: 12),
              _RecoveryLedgerLink(
                onTap: () => context.push('/recovery'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openClaimSheet(
    BuildContext context,
    WidgetRef ref,
    PaycheckItem item,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaycheckColors.paper,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Prepare claim', style: PaycheckType.title()),
              const SizedBox(height: 8),
              Text(item.label, style: PaycheckType.heading()),
              const SizedBox(height: 4),
              Text(
                '${_money(item.amount)} · ${item.dueLabel ?? 'No deadline found'}',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 22),
              const _ChecklistRow(
                title: 'Eligibility found',
                detail: 'Matched to the offer-letter benefit policy.',
              ),
              const _ChecklistRow(
                title: 'Supporting bill found',
                detail: 'The amount and billing month are readable.',
              ),
              const _ChecklistRow(
                title: 'You still approve submission',
                detail: 'ARTH prepares the pack. It never submits silently.',
                pending: true,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: PaycheckColors.ink,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    if (ref.read(paycheckProvider).usingSampleData) {
                      ref
                          .read(paycheckProvider.notifier)
                          .markClaimPrepared(item.id);
                    } else {
                      context.push(
                        '/recovery/claim/${Uri.encodeComponent(item.id)}',
                      );
                    }
                  },
                  child: Text(
                    'Prepare claim pack',
                    style: PaycheckType.bodyStrong(color: Colors.white),
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

class _IncomeSourceStrip extends StatelessWidget {
  const _IncomeSourceStrip({
    required this.income,
    required this.onEdit,
    required this.onAudit,
  });

  final IncomeSignal income;
  final VoidCallback onEdit;
  final VoidCallback onAudit;

  @override
  Widget build(BuildContext context) => Material(
        color: PaycheckColors.paper,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: PaycheckColors.ink),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MONTHLY PLANNING INCOME',
                            style: PaycheckType.sectionLabel(
                              color: PaycheckColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: income.hasIncome ? onAudit : onEdit,
                            child: Text(
                              income.hasIncome
                                  ? _money(income.monthlyIncome)
                                  : 'Not set',
                              style: PaycheckType.h2(),
                            ),
                          ),
                          Text(
                            income.sourceLabel,
                            style: PaycheckType.utility(
                              color: income.isEdited
                                  ? PaycheckColors.pending
                                  : PaycheckColors.matched,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit planning income',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _MoneySignalPath(),
              ],
            ),
          ),
        ),
      );
}

class _MoneySignalPath extends StatelessWidget {
  const _MoneySignalPath();

  @override
  Widget build(BuildContext context) {
    const labels = ['PAYCHECK', 'SPEND', 'GOAL', 'TAX'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Divider(color: PaycheckColors.line),
              ),
            ),
          Text(labels[index], style: PaycheckType.utility()),
        ],
      ],
    );
  }
}

Future<void> _editPlanningIncome(
  BuildContext context,
  WidgetRef ref,
  IncomeSignal income,
) async {
  final controller = TextEditingController(
    text: income.primaryMonthlyIncome > 0
        ? income.primaryMonthlyIncome.toString()
        : '',
  );
  String? errorText;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: PaycheckColors.paper,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly planning income', style: PaycheckType.h2()),
            const SizedBox(height: 6),
            Text(
              'One edit updates Home, Spend map, and Money goal. Other income stays separate.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (errorText != null) {
                  setSheetState(() => errorText = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Primary monthly income',
                prefixText: '₹ ',
                errorText: errorText,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (income.isEdited)
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(spendMapAdjustmentsProvider.notifier)
                          .clearManualPrimaryIncome();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Use detected income'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final amount = int.tryParse(controller.text) ?? 0;
                    if (amount <= 0) {
                      setSheetState(
                        () => errorText = 'Enter a monthly amount above zero.',
                      );
                      return;
                    }
                    await ref
                        .read(spendMapAdjustmentsProvider.notifier)
                        .setManualPrimaryIncome(amount);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Save income'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
}

class _RecoveryLedgerLink extends StatelessWidget {
  const _RecoveryLedgerLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PaycheckColors.ink,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Money recovery',
                      style: PaycheckType.bodyStrong(color: Colors.white),
                    ),
                    Text(
                      'Claims, benefits, payday check, and monthly history',
                      style: PaycheckType.utility(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPaycheck extends StatelessWidget {
  const _EmptyPaycheck({
    required this.offerLetterAdded,
    required this.onAddPayslip,
  });

  final bool offerLetterAdded;
  final VoidCallback onAddPayslip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: PaycheckColors.contractSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: PaycheckColors.contract,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Add your first payslip',
          key: const Key('paycheck_claimable_amount'),
          style: PaycheckType.title(),
        ),
        const SizedBox(height: 8),
        Text(
          'Upload your payslip, check the extracted numbers, and confirm your pay.',
          style: PaycheckType.body(color: PaycheckColors.inkSoft),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const Key('add_first_payslip'),
            onPressed: onAddPayslip,
            style: FilledButton.styleFrom(
              backgroundColor: PaycheckColors.ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              'Add payslip',
              style: PaycheckType.bodyStrong(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _EvidenceLine(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Offer letter',
          detail: offerLetterAdded ? 'Confirmed' : 'Not added yet',
          confirmed: offerLetterAdded,
        ),
      ],
    );
  }
}

class _ComparisonStrip extends StatelessWidget {
  const _ComparisonStrip({
    required this.paycheck,
    required this.onAudit,
  });

  final PaycheckState paycheck;
  final void Function(String id) onAudit;

  @override
  Widget build(BuildContext context) {
    final canCompare = paycheck.promisedMonthly > 0;
    final difference =
        canCompare ? paycheck.promisedMonthly - paycheck.grossReceived : 0;
    return Container(
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        border: Border.all(color: PaycheckColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _ComparisonCell(
            label: 'Promised',
            value: canCompare ? _money(paycheck.promisedMonthly) : 'Not added',
            onTap: canCompare ? () => onAudit('promised-pay') : null,
          ),
          Container(width: 1, height: 52, color: PaycheckColors.line),
          _ComparisonCell(
            label: 'Paid',
            value: _money(paycheck.grossReceived),
            color: PaycheckColors.matched,
            onTap:
                paycheck.grossReceived > 0 ? () => onAudit('gross-pay') : null,
          ),
          Container(width: 1, height: 52, color: PaycheckColors.line),
          _ComparisonCell(
            label: 'Difference',
            value: canCompare ? _money(difference.abs()) : '—',
            color:
                difference == 0 ? PaycheckColors.matched : PaycheckColors.claim,
            onTap: canCompare && paycheck.grossReceived > 0
                ? () => onAudit('pay-difference')
                : null,
          ),
        ],
      ),
    );
  }
}

class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell({
    required this.label,
    required this.value,
    this.color = PaycheckColors.ink,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: PaycheckType.utility()),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: PaycheckType.money(color: color, size: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchedPaycheckStatus extends StatelessWidget {
  const _MatchedPaycheckStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: PaycheckColors.matchedSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: PaycheckColors.matched,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Paycheck matched',
              style: PaycheckType.bodyStrong(color: PaycheckColors.matched),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaycheckBreakdown extends StatelessWidget {
  const _PaycheckBreakdown({required this.paycheck});

  final PaycheckState paycheck;

  @override
  Widget build(BuildContext context) {
    final deductions = paycheck.taxWithheld + paycheck.otherDeductions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paycheck summary', style: PaycheckType.heading()),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: PaycheckColors.paper,
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _AmountLine(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Gross earnings',
                value: paycheck.grossReceived,
                onTap: () => _openPayBreakdown(
                  context,
                  paycheck,
                  _PayBreakdownKind.earnings,
                ),
              ),
              _AmountLine(
                icon: Icons.remove_circle_outline,
                label: 'Deductions',
                value: deductions,
                onTap: () => _openPayBreakdown(
                  context,
                  paycheck,
                  _PayBreakdownKind.deductions,
                ),
              ),
              _AmountLine(
                icon: Icons.verified_outlined,
                label: 'Net pay',
                value: paycheck.netCredited,
                color: PaycheckColors.matched,
                last: true,
                onTap: () => _openPayBreakdown(
                  context,
                  paycheck,
                  _PayBreakdownKind.netPay,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.icon,
    required this.label,
    required this.value,
    this.color = PaycheckColors.ink,
    this.last = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: PaycheckColors.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: PaycheckColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: PaycheckType.body())),
            Text(_money(value), style: PaycheckType.money(color: color)),
            if (onTap != null) ...[
              const SizedBox(width: 7),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: PaycheckColors.inkSoft,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _PayBreakdownKind { earnings, deductions, netPay }

Future<void> _openPayBreakdown(
  BuildContext context,
  PaycheckState paycheck,
  _PayBreakdownKind kind,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PaycheckColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (context) => _PayBreakdownSheet(paycheck: paycheck, kind: kind),
  );
}

class _PayBreakdownSheet extends ConsumerWidget {
  const _PayBreakdownSheet({required this.paycheck, required this.kind});

  final PaycheckState paycheck;
  final _PayBreakdownKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = paycheck.components
        .where((item) => item.kind == PaycheckComponentKind.earning)
        .toList(growable: false);
    final deductions = paycheck.components
        .where((item) => item.kind == PaycheckComponentKind.deduction)
        .toList(growable: false);
    final title = switch (kind) {
      _PayBreakdownKind.earnings => 'Gross earnings',
      _PayBreakdownKind.deductions => 'Deductions',
      _PayBreakdownKind.netPay => 'Net pay calculation',
    };

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: PaycheckType.title())),
                if (kind != _PayBreakdownKind.netPay)
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: () => _openEditComponents(
                      context,
                      kind == _PayBreakdownKind.earnings
                          ? PaycheckComponentKind.earning
                          : PaycheckComponentKind.deduction,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (kind == _PayBreakdownKind.netPay) ...[
              _PayEquation(
                earnings: earnings,
                deductions: deductions,
                result: paycheck.netCredited,
              ),
              const SizedBox(height: 24),
              _BreakdownHeading(
                label: 'Gross earnings',
                value: paycheck.grossReceived,
              ),
              const SizedBox(height: 10),
              _ComponentGroups(
                components: earnings,
                kind: PaycheckComponentKind.earning,
              ),
              const SizedBox(height: 24),
              _BreakdownHeading(
                label: 'Less: deductions',
                value: paycheck.taxWithheld + paycheck.otherDeductions,
              ),
              const SizedBox(height: 10),
              _ComponentGroups(
                components: deductions,
                kind: PaycheckComponentKind.deduction,
              ),
            ] else ...[
              _PayEquation(
                earnings:
                    kind == _PayBreakdownKind.earnings ? earnings : const [],
                deductions: kind == _PayBreakdownKind.deductions
                    ? deductions
                    : const [],
                result: kind == _PayBreakdownKind.earnings
                    ? paycheck.grossReceived
                    : paycheck.taxWithheld + paycheck.otherDeductions,
                singleSide: true,
              ),
              const SizedBox(height: 24),
              _ComponentGroups(
                components:
                    kind == _PayBreakdownKind.earnings ? earnings : deductions,
                kind: kind == _PayBreakdownKind.earnings
                    ? PaycheckComponentKind.earning
                    : PaycheckComponentKind.deduction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the editor for one side (earnings or deductions) of the breakdown.
/// Net pay is derived from these, so it has no direct editor — see the
/// CALCULATION formula in [_PayEquation].
Future<void> _openEditComponents(
  BuildContext context,
  PaycheckComponentKind kind,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => _EditComponentsSheet(kind: kind),
  );
}

class _EditComponentsSheet extends ConsumerWidget {
  const _EditComponentsSheet({required this.kind});
  final PaycheckComponentKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final components = ref
        .watch(paycheckProvider)
        .components
        .where((c) => c.kind == kind)
        .toList(growable: false);
    final title = kind == PaycheckComponentKind.earning
        ? 'Edit earnings'
        : 'Edit deductions';

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: PaycheckType.title())),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Add categories the parser missed, or correct an amount.',
                style: PaycheckType.utility(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final component in components)
                        _EditComponentRow(component: component),
                      if (components.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Nothing here yet.',
                            style: PaycheckType.body(
                                color: PaycheckColors.inkSoft),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openAddComponent(context, ref, kind),
                icon: const Icon(Icons.add),
                label: Text(kind == PaycheckComponentKind.earning
                    ? 'Add earning'
                    : 'Add deduction'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditComponentRow extends ConsumerWidget {
  const _EditComponentRow({required this.component});
  final PaycheckComponent component;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openEditSingleComponent(context, ref, component),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(component.label,
                          style: PaycheckType.bodyStrong()),
                    ),
                    Text(_money(component.amount), style: PaycheckType.body()),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => ref
                .read(paycheckOverrideProvider.notifier)
                .removeComponent(component.canonicalKey, component.kind),
          ),
        ],
      ),
    );
  }
}

Future<void> _openEditSingleComponent(
  BuildContext context,
  WidgetRef ref,
  PaycheckComponent component,
) {
  final labelController = TextEditingController(text: component.label);
  final amountController =
      TextEditingController(text: component.amount.toString());
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit line item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: labelController,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '₹ amount'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                int.tryParse(amountController.text.replaceAll(',', '').trim());
            if (amount != null && amount >= 0) {
              ref.read(paycheckOverrideProvider.notifier).editComponent(
                    component.canonicalKey,
                    labelController.text,
                    amount,
                    component.kind,
                  );
            }
            Navigator.pop(dialogContext);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> _openAddComponent(
  BuildContext context,
  WidgetRef ref,
  PaycheckComponentKind kind,
) {
  final labelController = TextEditingController();
  final amountController = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(kind == PaycheckComponentKind.earning
          ? 'Add earning'
          : 'Add deduction'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: labelController,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '₹ amount'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                int.tryParse(amountController.text.replaceAll(',', '').trim());
            if (labelController.text.trim().isNotEmpty &&
                amount != null &&
                amount > 0) {
              ref
                  .read(paycheckOverrideProvider.notifier)
                  .addComponent(labelController.text, amount, kind);
            }
            Navigator.pop(dialogContext);
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

class _PayEquation extends StatelessWidget {
  const _PayEquation({
    required this.earnings,
    required this.deductions,
    required this.result,
    this.singleSide = false,
  });

  final List<PaycheckComponent> earnings;
  final List<PaycheckComponent> deductions;
  final int result;
  final bool singleSide;

  String _terms(List<PaycheckComponent> rows) => rows.isEmpty
      ? _money(0)
      : rows.map((row) => '${row.label} ${_money(row.amount)}').join(' + ');

  @override
  Widget build(BuildContext context) {
    final formula = singleSide
        ? '[ ${_terms(earnings.isNotEmpty ? earnings : deductions)} ] = ${_money(result)}'
        : '[ ${_terms(earnings)} ] − [ ${_terms(deductions)} ] = ${_money(result)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CALCULATION', style: PaycheckType.utility()),
          const SizedBox(height: 8),
          SelectableText(
            formula,
            style: PaycheckType.bodyStrong(),
          ),
        ],
      ),
    );
  }
}

class _BreakdownHeading extends StatelessWidget {
  const _BreakdownHeading({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label, style: PaycheckType.heading())),
          Text(_money(value), style: PaycheckType.money()),
        ],
      );
}

class _ComponentGroups extends StatelessWidget {
  const _ComponentGroups({required this.components, required this.kind});

  final List<PaycheckComponent> components;
  final PaycheckComponentKind kind;

  @override
  Widget build(BuildContext context) {
    if (components.isEmpty) {
      return Text(
        'No component rows were confirmed.',
        style: PaycheckType.body(color: PaycheckColors.inkSoft),
      );
    }
    final groups = <String, List<PaycheckComponent>>{};
    for (final component in components) {
      final parent = _parentCategory(component.classification, kind);
      groups.putIfAbsent(parent, () => []).add(component);
    }
    return Column(
      children: groups.entries.map((entry) {
        final total = entry.value.fold<int>(0, (sum, row) => sum + row.amount);
        final semanticGroups = <String, List<PaycheckComponent>>{};
        for (final row in entry.value) {
          semanticGroups.putIfAbsent(row.canonicalKey, () => []).add(row);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BreakdownHeading(label: entry.key, value: total),
              const SizedBox(height: 5),
              ...semanticGroups.entries.expand((semantic) {
                final semanticTotal =
                    semantic.value.fold<int>(0, (sum, row) => sum + row.amount);
                return [
                  Padding(
                    padding: const EdgeInsets.only(top: 9, bottom: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _semanticLabel(semantic.key),
                            style: PaycheckType.utility(),
                          ),
                        ),
                        Text(
                          _money(semanticTotal),
                          style: PaycheckType.utility(),
                        ),
                      ],
                    ),
                  ),
                  ...semantic.value.map(
                    (row) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: PaycheckColors.line),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(row.label, style: PaycheckType.body()),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _money(row.amount),
                            style: PaycheckType.bodyStrong(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
              }),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}

String _parentCategory(
  String classification,
  PaycheckComponentKind kind,
) {
  if (kind == PaycheckComponentKind.earning) {
    return switch (classification) {
      'basic_pay' || 'hra' || 'allowance' => 'Contractual pay',
      'bonus' || 'variable_pay' => 'Performance and variable pay',
      'reimbursement' => 'Reimbursements',
      _ => 'Adjustments and other earnings',
    };
  }
  return switch (classification) {
    'income_tax' || 'professional_tax' => 'Taxes',
    'employee_pf' ||
    'voluntary_pf' ||
    'employee_esi' =>
      'Retirement and social security',
    'insurance' => 'Insurance and benefits',
    'loan_repayment' ||
    'housing_recovery' ||
    'utility_recovery' ||
    'cooperative_recovery' =>
      'Recoveries and repayments',
    'welfare_contribution' => 'Welfare contributions',
    'salary_adjustment' => 'Payroll adjustments',
    _ => 'Other deductions',
  };
}

String _semanticLabel(String key) => key
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: PaycheckType.heading())),
        Text('$count', style: PaycheckType.utility()),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.item,
    required this.prepared,
    required this.onTap,
  });

  final PaycheckItem item;
  final bool prepared;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: prepared ? PaycheckColors.matchedSoft : PaycheckColors.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  prepared ? PaycheckColors.matchedSoft : PaycheckColors.line,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                prepared ? Icons.check_circle_rounded : Icons.error_outline,
                color: prepared ? PaycheckColors.matched : PaycheckColors.claim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: PaycheckType.bodyStrong()),
                    const SizedBox(height: 2),
                    Text(
                      prepared ? 'Ready to submit' : item.detail,
                      style: PaycheckType.utility(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_money(item.amount), style: PaycheckType.money()),
                  const SizedBox(height: 3),
                  Text(
                    prepared ? 'READY' : 'REVIEW',
                    style: PaycheckType.utility(
                      color: prepared
                          ? PaycheckColors.matched
                          : PaycheckColors.claim,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceStatus extends StatelessWidget {
  const _EvidenceStatus({
    required this.paycheck,
    required this.onOpenEvidence,
  });

  final PaycheckState paycheck;
  final VoidCallback onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    final hasPayslip = paycheck.evidence.any(
      (item) => item.kind == PaycheckEvidenceKind.payslip,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Documents', style: PaycheckType.heading())),
            TextButton(
              onPressed: onOpenEvidence,
              child: Text(
                'View all',
                style: PaycheckType.bodyStrong(
                  color: PaycheckColors.contract,
                ),
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: PaycheckColors.paper,
            border: Border.all(color: PaycheckColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _EvidenceLine(
                icon: Icons.description_outlined,
                title: 'Payslip',
                detail: hasPayslip ? 'Confirmed' : 'Not found',
                confirmed: hasPayslip,
              ),
              _EvidenceLine(
                icon: Icons.assignment_outlined,
                title: 'Offer letter',
                detail: paycheck.offerLetterAdded ? 'Confirmed' : 'Not added',
                confirmed: paycheck.offerLetterAdded,
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.icon,
    required this.title,
    required this.detail,
    required this.confirmed,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool confirmed;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Icon(icon, color: PaycheckColors.inkSoft, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyStrong()),
                Text(detail, style: PaycheckType.utility()),
              ],
            ),
          ),
          Icon(
            confirmed
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            color: confirmed ? PaycheckColors.matched : PaycheckColors.inkSoft,
            size: 20,
          ),
        ],
      ),
    );
  }
}

enum _InboxUploadState { idle, parsing, complete, failed }

class _InboxView extends ConsumerStatefulWidget {
  final PaycheckState paycheck;
  final bool exploreMode;
  final VoidCallback onPayslipApplied;

  const _InboxView({
    required this.paycheck,
    required this.exploreMode,
    required this.onPayslipApplied,
  });

  @override
  ConsumerState<_InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends ConsumerState<_InboxView> {
  _InboxUploadState _uploadState = _InboxUploadState.idle;
  String? _uploadMessage;

  Future<void> _addEvidence() async {
    if (widget.exploreMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign up to upload your own documents.'),
          action: SnackBarAction(
            label: 'SIGN UP',
            onPressed: () => context.go('/auth'),
          ),
        ),
      );
      return;
    }
    final uploadType = await showModalBottomSheet<_EvidenceUploadType>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What are you adding?', style: PaycheckType.heading()),
              const SizedBox(height: 12),
              ..._EvidenceUploadType.values.map(
                (type) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(type.icon, color: PaycheckColors.contract),
                  title: Text(type.label, style: PaycheckType.bodyStrong()),
                  subtitle: Text(
                    type.detail,
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheetContext, type),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (uploadType == null || !context.mounted) return;

    const evidenceTypes = XTypeGroup(
      label: 'Pay evidence',
      extensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [evidenceTypes]);
    if (file == null || !mounted) return;
    final lower = file.name.toLowerCase();
    final mimeType = lower.endsWith('.pdf')
        ? 'application/pdf'
        : lower.endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
    try {
      setState(() {
        _uploadState = _InboxUploadState.parsing;
        _uploadMessage = 'Preparing and reading ${file.name}';
      });
      final sourceBytes = await file.readAsBytes();
      List<int> uploadBytes = sourceBytes;
      var uploadFilename = file.name;
      var uploadMimeType = mimeType;
      String? ocrText;
      if (mimeType.startsWith('image/')) {
        final ocr = OnDeviceDocumentOcrService();
        final prepared = await ocr.prepareForUploadAsync(
          bytes: sourceBytes,
          filename: file.name,
        );
        uploadBytes = prepared.bytes;
        uploadFilename = prepared.filename;
        uploadMimeType = prepared.mimeType;
        if (uploadType == _EvidenceUploadType.payslip) {
          try {
            ocrText = await ocr.extractLatinTextFromPreparedImage(prepared);
          } catch (_) {
            // Sarvam and manual review remain available when device OCR fails.
          }
        }
      }
      if (uploadBytes.length > 8 * 1024 * 1024) {
        if (!mounted) return;
        setState(() {
          _uploadState = _InboxUploadState.failed;
          _uploadMessage = 'Could not reduce this image below 8 MB.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _uploadMessage = 'Uploading and reading $uploadFilename';
      });
      final uploaded = await ref.read(taxDocumentProvider.notifier).upload(
            documentType: uploadType.documentType,
            filename: uploadFilename,
            mimeType: uploadMimeType,
            bytes: uploadBytes,
            ocrText: ocrText,
          );
      if (!mounted) return;
      setState(() {
        _uploadState = _InboxUploadState.complete;
        _uploadMessage = uploaded.needsConfirmation
            ? 'Parsing complete. Check the extracted details.'
            : 'File saved. No structured details were found.';
      });
      if (uploaded.isPayslip &&
          uploaded.extractedFields.isNotEmpty &&
          mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _PayslipReviewSheet(
            document: uploaded,
            onApplied: widget.onPayslipApplied,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (error is StateError && error.message == 'not signed in') {
        await ref.read(authProvider.notifier).signOut();
        if (!mounted) return;
        context.go('/auth?mode=sign-in');
        return;
      }
      setState(() {
        _uploadState = _InboxUploadState.failed;
        _uploadMessage = error is ServerApiException
            ? error.message
            : 'Upload failed. Check your connection and try again.';
      });
    }
  }

  Future<bool> _confirmPermanentDelete(TaxDocument document) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this file permanently?'),
            content: Text(
              '${document.displayName} and its extracted details will be removed. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openDocument(TaxDocument document) async {
    if (document.isPayslip && document.extractedFields.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PayslipReviewSheet(
          document: document,
          onApplied: widget.onPayslipApplied,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(document.displayName, style: PaycheckType.heading()),
              const SizedBox(height: 6),
              Text(
                document.parseStatusLabel,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(taxDocumentProvider.notifier).updateMetadata(
                        document.id,
                        vaultStatus: document.archived ? 'active' : 'archived',
                      );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: Icon(document.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined),
                label: Text(document.archived ? 'Restore' : 'Archive'),
              ),
              TextButton.icon(
                onPressed: () async {
                  if (!await _confirmPermanentDelete(document)) return;
                  try {
                    await ref
                        .read(taxDocumentProvider.notifier)
                        .delete(document.id);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('File deleted permanently.')),
                      );
                    }
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error is ServerApiException
                            ? error.message
                            : 'Could not delete this file.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete permanently'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PaycheckEvidenceKind kind) => switch (kind) {
        PaycheckEvidenceKind.payslip => Icons.description_outlined,
        PaycheckEvidenceKind.receipt => Icons.receipt_long_outlined,
        PaycheckEvidenceKind.salaryAlert => Icons.sms_outlined,
        PaycheckEvidenceKind.document => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final documents =
        ref.watch(taxDocumentProvider).asData?.value ?? const <TaxDocument>[];
    final documentsById = {
      for (final document in documents) document.id: document
    };
    return _PageFrame(
      eyebrow: 'Documents',
      title: 'Documents behind your pay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: PaycheckColors.matchedSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: PaycheckColors.matched,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Read-only. ARTH cannot move money or send email.',
                    style: PaycheckType.body(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('add_paycheck_evidence'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: PaycheckColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _uploadState == _InboxUploadState.parsing
                  ? null
                  : _addEvidence,
              icon: _uploadState == _InboxUploadState.parsing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _uploadState == _InboxUploadState.parsing
                    ? 'Uploading and parsing'
                    : 'Scan or upload evidence',
                style: PaycheckType.bodyStrong(color: Colors.white),
              ),
            ),
          ),
          if (_uploadMessage != null) ...[
            const SizedBox(height: 10),
            _InboxStatus(
              state: _uploadState,
              message: _uploadMessage!,
            ),
          ],
          if (widget.paycheck.sources.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Connected evidence', style: PaycheckType.heading()),
            const SizedBox(height: 8),
            ...widget.paycheck.sources.map(
              (source) => _SourceRow(
                source: source,
                onToggle: source.name == 'Gmail receipts'
                    ? (value) => ref
                        .read(paycheckProvider.notifier)
                        .setInboxConnected(value)
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: Text('Your files', style: PaycheckType.heading())),
              Text('${widget.paycheck.evidence.length}',
                  style: PaycheckType.utility()),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.paycheck.evidence.isEmpty)
            Text(
              'No files yet. Add a payslip to start.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
          ...widget.paycheck.evidence.map(
            (item) {
              final document = documentsById[item.id];
              return _DetectedDocument(
                icon: _iconFor(item.kind),
                title: item.name,
                detail: item.detail,
                badge: item.statusLabel,
                attention: item.needsAction,
                onTap: document == null ? null : () => _openDocument(document),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InboxStatus extends StatelessWidget {
  const _InboxStatus({required this.state, required this.message});

  final _InboxUploadState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final failed = state == _InboxUploadState.failed;
    final complete = state == _InboxUploadState.complete;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: failed
            ? PaycheckColors.claimSoft
            : complete
                ? PaycheckColors.matchedSoft
                : PaycheckColors.contractSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (state == _InboxUploadState.parsing)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 19,
              color: failed ? PaycheckColors.claim : PaycheckColors.matched,
            ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: PaycheckType.body())),
        ],
      ),
    );
  }
}

enum _EvidenceUploadType {
  payslip(
    documentType: 'payslip',
    label: 'Payslip',
    detail: 'Extract earnings, deductions, payable days and net salary.',
    icon: Icons.payments_outlined,
  ),
  offerLetter(
    documentType: 'offerLetter',
    label: 'Offer letter',
    detail: 'Extract the compensation promised by your employer.',
    icon: Icons.description_outlined,
  ),
  other(
    documentType: 'otherTaxDocument',
    label: 'Receipt or other proof',
    detail: 'Store evidence for manual review and later matching.',
    icon: Icons.receipt_long_outlined,
  );

  const _EvidenceUploadType({
    required this.documentType,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String documentType;
  final String label;
  final String detail;
  final IconData icon;
}

class _PayslipReviewSheet extends ConsumerStatefulWidget {
  const _PayslipReviewSheet({
    required this.document,
    required this.onApplied,
  });

  final TaxDocument document;
  final VoidCallback onApplied;

  @override
  ConsumerState<_PayslipReviewSheet> createState() =>
      _PayslipReviewSheetState();
}

class _PayslipReviewSheetState extends ConsumerState<_PayslipReviewSheet> {
  bool _confirming = false;
  String? _error;

  Map<String, dynamic> get _fields => widget.document.confirmedFields.isNotEmpty
      ? widget.document.confirmedFields
      : widget.document.extractedFields;

  Map<String, dynamic> _map(String key) =>
      _fields[key] as Map<String, dynamic>? ?? const {};

  List<Map<String, dynamic>> _rows(String key) =>
      (_fields[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  String _amount(dynamic value) {
    if (value is! num) return 'Not found';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }

  Future<void> _confirm() async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.of(context);
      final confirmed = await ref
          .read(taxDocumentProvider.notifier)
          .confirmParsedFields(widget.document.id);
      final documents = ref.read(taxDocumentProvider).asData?.value ??
          <TaxDocument>[confirmed];
      ref.read(paycheckProvider.notifier).syncDocuments(documents);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onApplied();
      messenger.showSnackBar(
        const SnackBar(content: Text('Payslip confirmed. Home is updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = error is ServerApiException
            ? error.message
            : 'Could not confirm these fields. Try again.';
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this payslip permanently?'),
            content: Text(
              '${widget.document.displayName} and all extracted salary details will be removed. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(taxDocumentProvider.notifier).delete(widget.document.id);
      final documents = ref.read(taxDocumentProvider).asData?.value ?? const [];
      ref.read(paycheckProvider.notifier).syncDocuments(documents);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Payslip deleted permanently.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = error is ServerApiException
            ? error.message
            : 'Could not delete this payslip.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendance = _map('attendance');
    final earnings = _rows('earnings');
    final deductions = _rows('deductions');
    final warnings = (_fields['warnings'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
    final questions =
        (_fields['questionsForUser'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.58,
        maxChildSize: 0.96,
        builder: (context, scrollController) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
                children: [
                  Text(
                    widget.document.needsConfirmation
                        ? 'Review payslip'
                        : 'Payslip details',
                    style: PaycheckType.title(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_fields['payPeriod'] ?? 'Pay period not found'} · ${_fields['employerName'] ?? 'Employer not found'}',
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check these numbers against your payslip. Confirm only if they match.',
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                  const SizedBox(height: 24),
                  const _PayslipSectionTitle('Attendance'),
                  _PayslipGrid(
                    values: [
                      ('Actual payable', attendance['actualPayableDays']),
                      ('Working days', attendance['totalWorkingDays']),
                      ('Loss of pay', attendance['lossOfPayDays']),
                      ('Days payable', attendance['daysPayable']),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _PayslipSectionTitle(
                    'Earnings',
                    count: earnings.length,
                  ),
                  ...earnings.map(
                    (row) => _PayslipAmountRow(
                      label: row['label']?.toString() ?? 'Earning',
                      amount: _amount(row['amount']),
                    ),
                  ),
                  _PayslipAmountRow(
                    label: 'Gross earnings',
                    amount: _amount(_fields['grossEarnings']),
                    strong: true,
                  ),
                  const SizedBox(height: 24),
                  _PayslipSectionTitle(
                    'Deductions',
                    count: deductions.length,
                  ),
                  ...deductions.map(
                    (row) => _PayslipAmountRow(
                      label: row['label']?.toString() ?? 'Deduction',
                      amount: _amount(row['amount']),
                    ),
                  ),
                  _PayslipAmountRow(
                    label: 'Total deductions',
                    amount: _amount(_fields['totalDeductions']),
                    strong: true,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: PaycheckColors.matchedSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _PayslipAmountRow(
                      label: 'Net salary',
                      amount: _amount(_fields['netSalary']),
                      strong: true,
                      border: false,
                    ),
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PaycheckColors.claimSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Check before confirming',
                              style: PaycheckType.bodyStrong()),
                          const SizedBox(height: 6),
                          ...warnings.map(
                            (warning) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                warning,
                                style: PaycheckType.body(
                                  color: PaycheckColors.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (questions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PaycheckColors.contractSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Details ARTH could not confirm',
                              style: PaycheckType.bodyStrong()),
                          const SizedBox(height: 6),
                          ...questions.map(
                            (question) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '• $question',
                                style: PaycheckType.body(
                                  color: PaycheckColors.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: PaycheckType.body(color: PaycheckColors.claim)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Delete permanently',
                    onPressed: _confirming ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed:
                            _confirming || !widget.document.needsConfirmation
                                ? null
                                : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: PaycheckColors.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          _confirming
                              ? 'Saving...'
                              : widget.document.needsConfirmation
                                  ? 'Use these payslip details'
                                  : 'Already used in Home',
                          style: PaycheckType.bodyStrong(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayslipSectionTitle extends StatelessWidget {
  const _PayslipSectionTitle(this.title, {this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          count == null
              ? title.toUpperCase()
              : '${title.toUpperCase()} ($count)',
          style: PaycheckType.utility(),
        ),
      );
}

class _PayslipGrid extends StatelessWidget {
  const _PayslipGrid({required this.values});

  final List<(String, dynamic)> values;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.25,
        children: values
            .map(
              (item) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PaycheckColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$1, style: PaycheckType.utility()),
                    const Spacer(),
                    Text('${item.$2 ?? 'Not found'}',
                        style: PaycheckType.bodyStrong()),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      );
}

class _PayslipAmountRow extends StatelessWidget {
  const _PayslipAmountRow({
    required this.label,
    required this.amount,
    this.strong = false,
    this.border = true,
  });

  final String label;
  final String amount;
  final bool strong;
  final bool border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: border
              ? const Border(bottom: BorderSide(color: PaycheckColors.line))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: strong ? PaycheckType.bodyStrong() : PaycheckType.body(),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amount,
              style: strong ? PaycheckType.bodyStrong() : PaycheckType.body(),
            ),
          ],
        ),
      );
}

class _YouView extends ConsumerWidget {
  final PaycheckState paycheck;

  const _YouView({required this.paycheck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProfessionalProfileView(paycheck: paycheck);
  }
}

class _TaxOverviewView extends ConsumerWidget {
  const _TaxOverviewView({required this.paycheck});

  final PaycheckState paycheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impact = ref.watch(paycheckTaxImpactProvider);
    final hints = ref.watch(paycheckTaxHintsProvider);
    return _PageFrame(
      eyebrow: 'Filing',
      title: 'Plan with confirmed numbers.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PaycheckColors.paper,
              border: Border.all(color: PaycheckColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _TaxSummaryLine(
                  label: 'Gross pay this period',
                  value: paycheck.grossReceived > 0
                      ? _money(paycheck.grossReceived)
                      : 'Add payslip',
                ),
                _TaxSummaryLine(
                  label: 'Tax withheld',
                  value: paycheck.taxWithheld > 0
                      ? _money(paycheck.taxWithheld)
                      : 'Not confirmed',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Paycheck tax impact', style: PaycheckType.heading()),
          const SizedBox(height: 10),
          _TaxImpactCard(impact: impact),
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Payslip tax signals', style: PaycheckType.heading()),
            const SizedBox(height: 10),
            for (var index = 0; index < hints.length; index++)
              _TaxHintRow(
                hint: hints[index],
                last: index == hints.length - 1,
              ),
          ],
          const SizedBox(height: 18),
          Text(
            'ARTH compares tax regimes using versioned rules. Your confirmed documents remain the source of truth.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: const Key('open_tax_plan'),
              onPressed: () => context.push('/tax-plan'),
              style: FilledButton.styleFrom(
                backgroundColor: PaycheckColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.calculate_outlined),
              label: Text(
                'Open tax plan',
                style: PaycheckType.bodyStrong(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxImpactCard extends StatelessWidget {
  const _TaxImpactCard({required this.impact});

  final PaycheckTaxImpact impact;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (impact.status) {
      TdsPaceStatus.over || TdsPaceStatus.under => (
          PaycheckColors.claim,
          PaycheckColors.claimSoft,
        ),
      TdsPaceStatus.aligned => (
          PaycheckColors.matched,
          PaycheckColors.matchedSoft,
        ),
      TdsPaceStatus.calculating ||
      TdsPaceStatus.unavailable ||
      TdsPaceStatus.unknown =>
        (
          PaycheckColors.inkSoft,
          PaycheckColors.surfaceMuted,
        ),
    };
    final difference = impact.difference.abs();
    final detail = switch (impact.status) {
      TdsPaceStatus.calculating =>
        'ARTH is calculating the rule estimate for your selected regime.',
      TdsPaceStatus.unavailable =>
        'The tax estimate could not load. Open the tax plan to retry.',
      TdsPaceStatus.unknown =>
        'Confirm a payslip to compare payroll TDS with ARTH tax rules.',
      TdsPaceStatus.aligned =>
        'Payslip TDS is near the monthly estimate for ${impact.regimeLabel}.',
      TdsPaceStatus.over =>
        '${_money(difference)} more TDS than the monthly estimate. Check payroll inputs and declared regime.',
      TdsPaceStatus.under =>
        '${_money(difference)} less TDS than the monthly estimate. Review before year-end.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            impact.status.label,
            style: PaycheckType.sectionLabel(color: color),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TaxPaceFigure(
                  label: 'Payslip TDS',
                  value: impact.actualMonthlyTds,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TaxPaceFigure(
                  label: 'Rule estimate',
                  value: impact.status == TdsPaceStatus.calculating
                      ? null
                      : impact.expectedMonthlyTds,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(detail, style: PaycheckType.body()),
          const SizedBox(height: 6),
          Text(
            'Review signal only. Not a filing instruction.',
            style: PaycheckType.utility(),
          ),
        ],
      ),
    );
  }
}

class _TaxPaceFigure extends StatelessWidget {
  const _TaxPaceFigure({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PaycheckType.utility()),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? 'Calculating' : _money(value!),
              style: PaycheckType.money(size: 18),
            ),
          ),
        ],
      );
}

class _TaxHintRow extends StatelessWidget {
  const _TaxHintRow({required this.hint, required this.last});

  final PaycheckTaxHint hint;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: PaycheckColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: PaycheckColors.contractSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hint.kind.label,
                style: PaycheckType.utility(color: PaycheckColors.contract),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hint.title, style: PaycheckType.bodyStrong()),
                  const SizedBox(height: 3),
                  Text(
                    hint.detail,
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TaxSummaryLine extends StatelessWidget {
  const _TaxSummaryLine({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: PaycheckType.body())),
          const SizedBox(width: 12),
          Text(value, style: PaycheckType.money()),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool sample;
  final VoidCallback onOpenSettings;

  const _TopBar({required this.sample, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArthBrandMark(
          size: 30,
          spacing: 9,
          wordmarkStyle: PaycheckType.heading(),
        ),
        const Spacer(),
        if (sample) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: PaycheckColors.contractSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Sample',
              style: PaycheckType.utility(color: PaycheckColors.contract),
            ),
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined,
              color: PaycheckColors.inkSoft),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _PageFrame extends StatelessWidget {
  final String eyebrow;
  final String title;
  final Widget child;

  const _PageFrame({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArthBrandMark(
              size: 30,
              spacing: 9,
              wordmarkStyle: PaycheckType.heading(),
            ),
            const SizedBox(height: 26),
            Text(eyebrow, style: PaycheckType.utility()),
            const SizedBox(height: 7),
            Text(title, style: PaycheckType.title()),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final PaycheckSource source;
  final ValueChanged<bool>? onToggle;

  const _SourceRow({required this.source, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: source.connected
                  ? PaycheckColors.matchedSoft
                  : PaycheckColors.paper,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              source.connected ? Icons.check_rounded : Icons.add_rounded,
              color: source.connected
                  ? PaycheckColors.matched
                  : PaycheckColors.inkSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name, style: PaycheckType.bodyStrong()),
                Text(
                  source.detail,
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
          if (onToggle != null)
            Switch.adaptive(
              value: source.connected,
              activeTrackColor: PaycheckColors.matched,
              onChanged: onToggle,
            )
          else
            Text(
              source.connected ? 'ON' : 'ADD',
              style: PaycheckType.utility(
                color: source.connected
                    ? PaycheckColors.matched
                    : PaycheckColors.contract,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetectedDocument extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String badge;
  final bool attention;
  final VoidCallback? onTap;

  const _DetectedDocument({
    required this.icon,
    required this.title,
    required this.detail,
    required this.badge,
    this.attention = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: PaycheckColors.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PaycheckType.bodyStrong()),
                      Text(
                        detail,
                        style: PaycheckType.body(color: PaycheckColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Text(
                  badge,
                  style: PaycheckType.utility(
                    color: attention
                        ? PaycheckColors.claim
                        : PaycheckColors.matched,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: PaycheckColors.inkSoft,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String title;
  final String detail;
  final bool pending;

  const _ChecklistRow({
    required this.title,
    required this.detail,
    this.pending = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: pending
                  ? PaycheckColors.claimSoft
                  : PaycheckColors.matchedSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              pending ? Icons.person_outline_rounded : Icons.check_rounded,
              size: 15,
              color: pending ? PaycheckColors.claim : PaycheckColors.matched,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyStrong()),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaycheckNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _PaycheckNav({
    required this.selectedIndex,
    required this.onSelected,
  });

  static const items = [
    (
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
      'Home'
    ),
    (Icons.description_outlined, Icons.description_rounded, 'Documents'),
    (Icons.calculate_outlined, Icons.calculate_rounded, 'Filing'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 7, 8, 7 + bottom),
      decoration: const BoxDecoration(
        color: PaycheckColors.paper,
        border: Border(top: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final selected = selectedIndex == index;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: item.$3,
              child: InkWell(
                key: Key('paycheck_nav_${item.$3.toLowerCase()}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(index),
                child: SizedBox(
                  height: 58,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? item.$2 : item.$1,
                        size: 21,
                        color: selected
                            ? PaycheckColors.ink
                            : PaycheckColors.inkSoft,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        maxLines: 1,
                        style: PaycheckType.utility(
                          color: selected
                              ? PaycheckColors.ink
                              : PaycheckColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
