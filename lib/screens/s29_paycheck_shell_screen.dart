import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/paycheck.dart';
import '../providers/paycheck_provider.dart';
import '../theme/paycheck_theme.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

class PaycheckShellScreen extends ConsumerStatefulWidget {
  final int initialIndex;

  const PaycheckShellScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<PaycheckShellScreen> createState() =>
      _PaycheckShellScreenState();
}

class _PaycheckShellScreenState extends ConsumerState<PaycheckShellScreen> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final paycheck = ref.watch(paycheckProvider);
    final pages = [
      _PaycheckHome(paycheck: paycheck),
      _PromiseView(paycheck: paycheck),
      _InboxView(paycheck: paycheck),
      _YouView(paycheck: paycheck),
    ];

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _PaycheckNav(
        selectedIndex: _index,
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _PaycheckHome extends ConsumerWidget {
  final PaycheckState paycheck;

  const _PaycheckHome({required this.paycheck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimItems = paycheck.items
        .where((item) => item.status == PaycheckItemStatus.claimable)
        .toList(growable: false);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              period: paycheck.payPeriod,
              sample: paycheck.usingSampleData,
            ),
            const SizedBox(height: 28),
            Text('READY TO CLAIM', style: PaycheckType.utility()),
            const SizedBox(height: 7),
            Text(
              _money(paycheck.claimableNow),
              key: const Key('paycheck_claimable_amount'),
              style: PaycheckType.display(color: PaycheckColors.claim),
            ),
            const SizedBox(height: 8),
            Text(
              'Two benefits have matching bills. Prepare both before the July payroll closes.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 22),
            _ReconciliationCard(paycheck: paycheck),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Money needing action',
                    style: PaycheckType.heading(),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${claimItems.length} ITEMS',
                    style: PaycheckType.utility()),
              ],
            ),
            const SizedBox(height: 12),
            ...claimItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ClaimCard(
                  item: item,
                  prepared: paycheck.preparedClaims.contains(item.id),
                  onTap: () => _openClaimSheet(context, ref, item),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PayPeriodStrip(paycheck: paycheck),
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
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    ref
                        .read(paycheckProvider.notifier)
                        .markClaimPrepared(item.id);
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${item.label} pack prepared')),
                    );
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

class _PromiseView extends StatelessWidget {
  final PaycheckState paycheck;

  const _PromiseView({required this.paycheck});

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      eyebrow: 'COMPENSATION CONTRACT',
      title: 'What your employer\npromised.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: PaycheckColors.ink,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paycheck.employer.toUpperCase(),
                  style: PaycheckType.utility(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                Text(
                  _money(paycheck.promisedMonthly),
                  style: PaycheckType.display(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'monthly employer cost currently tracked',
                  style: PaycheckType.body(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: paycheck.reconciliationPercent / 100,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(
                      PaycheckColors.matched,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${paycheck.reconciliationPercent}% reconciled this month',
                  style: PaycheckType.utility(color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Contract ledger', style: PaycheckType.heading()),
          const SizedBox(height: 12),
          ...paycheck.items.map((item) => _PromiseRow(item: item)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PaycheckColors.contractSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: PaycheckColors.contract,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_money(paycheck.pendingAmount)} variable pay is expected with September payroll.',
                    style: PaycheckType.bodyStrong(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxView extends ConsumerWidget {
  final PaycheckState paycheck;

  const _InboxView({required this.paycheck});

  Future<void> _addEvidence(BuildContext context, WidgetRef ref) async {
    const evidenceTypes = XTypeGroup(
      label: 'Pay evidence',
      extensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [evidenceTypes]);
    if (file == null || !context.mounted) return;
    ref.read(paycheckProvider.notifier).addEvidence(file.name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${file.name} added for review')),
    );
  }

  IconData _iconFor(PaycheckEvidenceKind kind) => switch (kind) {
        PaycheckEvidenceKind.payslip => Icons.description_outlined,
        PaycheckEvidenceKind.receipt => Icons.receipt_long_outlined,
        PaycheckEvidenceKind.salaryAlert => Icons.sms_outlined,
        PaycheckEvidenceKind.document => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PageFrame(
      eyebrow: 'READ-ONLY SOURCES',
      title: 'Proof, without\npayment access.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PaycheckColors.matchedSoft,
              borderRadius: BorderRadius.circular(14),
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
                    'ARTH reads compensation evidence. It cannot send email, move money or approve a claim.',
                    style: PaycheckType.bodyStrong(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('add_paycheck_evidence'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: PaycheckColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _addEvidence(context, ref),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(
                'Scan or upload evidence',
                style: PaycheckType.bodyStrong(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Offer letters, payslips, gym receipts, bills or salary alerts.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 24),
          Text('Connected evidence', style: PaycheckType.heading()),
          const SizedBox(height: 10),
          ...paycheck.sources.map(
            (source) => _SourceRow(
              source: source,
              onToggle: source.name == 'Gmail receipts'
                  ? (value) => ref
                      .read(paycheckProvider.notifier)
                      .setInboxConnected(value)
                  : null,
            ),
          ),
          const SizedBox(height: 26),
          Text('Found this month', style: PaycheckType.heading()),
          const SizedBox(height: 10),
          ...paycheck.evidence.map(
            (item) => _DetectedDocument(
              icon: _iconFor(item.kind),
              title: item.name,
              detail: item.detail,
              badge: item.statusLabel,
              attention: item.needsAction,
            ),
          ),
        ],
      ),
    );
  }
}

class _YouView extends StatelessWidget {
  final PaycheckState paycheck;

  const _YouView({required this.paycheck});

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      eyebrow: 'YOUR PAY PROFILE',
      title: paycheck.employeeName,
      subtitle: '${paycheck.role}\n${paycheck.employer}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileMetric(
            label: 'ANNUAL BENEFITS TRACKED',
            value: _money(paycheck.annualBenefits),
            detail: 'Outside monthly fixed pay',
          ),
          const SizedBox(height: 12),
          _ProfileMetric(
            label: 'JULY NET CREDIT',
            value: _money(paycheck.netCredited),
            detail: 'Matched to salary alert',
          ),
          const SizedBox(height: 26),
          Text('Controls', style: PaycheckType.heading()),
          const SizedBox(height: 10),
          const _SettingsRow(
            icon: Icons.lock_outline_rounded,
            title: 'Data and permissions',
            detail: 'Review or remove every source',
          ),
          const _SettingsRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete paycheck data',
            detail: 'Permanent and immediate',
          ),
          const SizedBox(height: 24),
          Text('Small tools', style: PaycheckType.heading()),
          const SizedBox(height: 10),
          Material(
            color: PaycheckColors.paper,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: const Key('tax_plan_tool'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/tax-plan'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: PaycheckColors.contractSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calculate_outlined,
                        color: PaycheckColors.contract,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Plan your tax',
                              style: PaycheckType.bodyStrong()),
                          const SizedBox(height: 3),
                          Text(
                            'Run the ARTH tax-gap diagnostic.',
                            style: PaycheckType.body(
                              color: PaycheckColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: PaycheckColors.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String period;
  final bool sample;

  const _TopBar({required this.period, required this.sample});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('ARTH', style: PaycheckType.heading()),
        const SizedBox(width: 10),
        Container(width: 1, height: 18, color: PaycheckColors.line),
        const SizedBox(width: 10),
        Flexible(
          child: Text(period.toUpperCase(), style: PaycheckType.utility()),
        ),
        const Spacer(),
        if (sample)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: PaycheckColors.contractSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'SAMPLE',
              style: PaycheckType.utility(color: PaycheckColors.contract),
            ),
          ),
      ],
    );
  }
}

class _ReconciliationCard extends StatelessWidget {
  final PaycheckState paycheck;

  const _ReconciliationCard({required this.paycheck});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'JULY RECONCILIATION',
                  style: PaycheckType.utility(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PaycheckColors.matchedSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${paycheck.reconciliationPercent}% MATCHED',
                  style: PaycheckType.utility(color: PaycheckColors.matched),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _RailRow(
            color: PaycheckColors.contract,
            label: 'Promised',
            value: _money(paycheck.promisedMonthly),
            detail: 'Offer letter',
            isFirst: true,
          ),
          _RailRow(
            color: PaycheckColors.matched,
            label: 'Gross received',
            value: _money(paycheck.grossReceived),
            detail: 'July payslip',
          ),
          _RailRow(
            color: PaycheckColors.claim,
            label: 'Still claimable',
            value: _money(paycheck.claimableNow),
            detail: '2 eligible benefits',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final String detail;
  final bool isFirst;
  final bool isLast;

  const _RailRow({
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isFirst)
                  Positioned(
                      top: 0,
                      bottom: 18,
                      child: Container(width: 2, color: PaycheckColors.line)),
                if (!isLast)
                  Positioned(
                      top: 18,
                      bottom: 0,
                      child: Container(width: 2, color: PaycheckColors.line)),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: PaycheckColors.paper, width: 3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: PaycheckType.bodyStrong()),
                  Text(
                    detail,
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          Text(value, style: PaycheckType.bodyStrong(color: color)),
        ],
      ),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  final PaycheckItem item;
  final bool prepared;
  final VoidCallback onTap;

  const _ClaimCard({
    required this.item,
    required this.prepared,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: prepared ? PaycheckColors.matchedSoft : PaycheckColors.claimSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      prepared ? PaycheckColors.matched : PaycheckColors.claim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  prepared ? Icons.check_rounded : Icons.arrow_outward_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.label,
                              style: PaycheckType.bodyStrong()),
                        ),
                        Text(_money(item.amount),
                            style: PaycheckType.heading()),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prepared
                          ? 'Claim pack ready for your review'
                          : item.detail,
                      style: PaycheckType.body(color: PaycheckColors.inkSoft),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      prepared ? 'PREPARED' : item.dueLabel!.toUpperCase(),
                      style: PaycheckType.utility(
                        color: prepared
                            ? PaycheckColors.matched
                            : PaycheckColors.claim,
                      ),
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

class _PayPeriodStrip extends StatelessWidget {
  final PaycheckState paycheck;

  const _PayPeriodStrip({required this.paycheck});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, color: PaycheckColors.contract),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next payroll check', style: PaycheckType.bodyStrong()),
                Text(
                  '31 July · after net salary credit',
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
          Text('9 DAYS', style: PaycheckType.utility()),
        ],
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  const _PageFrame({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ARTH', style: PaycheckType.heading()),
            const SizedBox(height: 34),
            Text(eyebrow, style: PaycheckType.utility()),
            const SizedBox(height: 7),
            Text(title, style: PaycheckType.title()),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
            ],
            const SizedBox(height: 26),
            child,
          ],
        ),
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  final PaycheckItem item;

  const _PromiseRow({required this.item});

  Color get _color => switch (item.status) {
        PaycheckItemStatus.matched => PaycheckColors.matched,
        PaycheckItemStatus.claimable => PaycheckColors.claim,
        PaycheckItemStatus.pending => PaycheckColors.pending,
        PaycheckItemStatus.deduction => PaycheckColors.inkSoft,
        PaycheckItemStatus.review => PaycheckColors.contract,
      };

  String get _state => switch (item.status) {
        PaycheckItemStatus.matched => 'MATCHED',
        PaycheckItemStatus.claimable => 'CLAIM',
        PaycheckItemStatus.pending => 'PENDING',
        PaycheckItemStatus.deduction => 'DEDUCTED',
        PaycheckItemStatus.review => 'VERIFY',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: PaycheckType.bodyStrong()),
                Text(
                  item.detail,
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(item.amount), style: PaycheckType.bodyStrong()),
              Text(_state, style: PaycheckType.utility(color: _color)),
            ],
          ),
        ],
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
              borderRadius: BorderRadius.circular(12),
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

  const _DetectedDocument({
    required this.icon,
    required this.title,
    required this.detail,
    required this.badge,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(14),
      ),
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
              color: attention ? PaycheckColors.claim : PaycheckColors.matched,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  final String label;
  final String value;
  final String detail;

  const _ProfileMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PaycheckType.utility()),
          const SizedBox(height: 8),
          Text(value, style: PaycheckType.title()),
          const SizedBox(height: 3),
          Text(
            detail,
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
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
          const Icon(
            Icons.chevron_right_rounded,
            color: PaycheckColors.inkSoft,
          ),
        ],
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
    (Icons.payments_outlined, Icons.payments_rounded, 'Paycheck'),
    (Icons.assignment_outlined, Icons.assignment_rounded, 'Promise'),
    (Icons.inbox_outlined, Icons.inbox_rounded, 'Inbox'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'You'),
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
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        ).copyWith(fontSize: 9.5),
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
