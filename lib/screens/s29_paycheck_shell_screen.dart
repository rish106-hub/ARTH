import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/paycheck.dart';
import '../models/tax_document.dart';
import '../providers/paycheck_provider.dart';
import '../providers/tax_document_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 3);
    if (widget.exploreMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(paycheckProvider.notifier).useSampleData();
      });
    }
  }

  @override
  void dispose() {
    if (widget.exploreMode) {
      ref.read(paycheckProvider.notifier).closeSampleData();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paycheck = ref.watch(paycheckProvider);
    final pages = [
      _PaycheckHome(paycheck: paycheck),
      _PromiseView(paycheck: paycheck),
      _InboxView(paycheck: paycheck, exploreMode: widget.exploreMode),
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

  const _PaycheckHome({required this.paycheck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimItems = paycheck.items
        .where((item) => item.status == PaycheckItemStatus.claimable)
        .toList(growable: false);
    final hasPayslip = paycheck.grossReceived > 0 || paycheck.netCredited > 0;
    final headline = claimItems.isNotEmpty
        ? 'READY TO CLAIM'
        : hasPayslip
            ? 'NET PAY THIS PERIOD'
            : 'NO PAYSLIP CONFIRMED';
    final headlineValue =
        claimItems.isNotEmpty ? paycheck.claimableNow : paycheck.netCredited;
    final summary = claimItems.isNotEmpty
        ? '${claimItems.length} ${claimItems.length == 1 ? 'benefit has' : 'benefits have'} matching proof. Review before the payroll deadline.'
        : hasPayslip
            ? 'Your confirmed payslip shows ${_money(paycheck.grossReceived)} in earnings and ${_money(paycheck.taxWithheld + paycheck.otherDeductions)} in deductions.'
            : 'Add a payslip in Inbox, check the extracted numbers, then confirm them here.';

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
            Text(headline, style: PaycheckType.utility()),
            const SizedBox(height: 7),
            if (hasPayslip || claimItems.isNotEmpty)
              Text(
                _money(headlineValue),
                key: const Key('paycheck_claimable_amount'),
                style: PaycheckType.display(
                  color: claimItems.isNotEmpty
                      ? PaycheckColors.claim
                      : PaycheckColors.matched,
                ),
              )
            else
              Text(
                'Add your first payslip',
                key: const Key('paycheck_claimable_amount'),
                style: PaycheckType.title(),
              ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 22),
            _ReconciliationCard(paycheck: paycheck),
            const SizedBox(height: 26),
            if (claimItems.isNotEmpty) ...[
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
            ],
            if (hasPayslip) _PayPeriodStrip(paycheck: paycheck),
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
  final bool exploreMode;

  const _InboxView({required this.paycheck, required this.exploreMode});

  Future<void> _addEvidence(BuildContext context, WidgetRef ref) async {
    if (exploreMode) {
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
    if (file == null || !context.mounted) return;
    final lower = file.name.toLowerCase();
    final mimeType = lower.endsWith('.pdf')
        ? 'application/pdf'
        : lower.endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
    try {
      final uploaded = await ref.read(taxDocumentProvider.notifier).upload(
            documentType: uploadType.documentType,
            filename: file.name,
            mimeType: mimeType,
            bytes: await file.readAsBytes(),
          );
      if (!context.mounted) return;
      ref.read(paycheckProvider.notifier).addEvidence(file.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} added for review')),
      );
      if (uploadType == _EvidenceUploadType.payslip &&
          uploaded.extractedFields.isNotEmpty &&
          context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _PayslipReviewSheet(document: uploaded),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Check your connection and try again.'),
        ),
      );
    }
  }

  IconData _iconFor(PaycheckEvidenceKind kind) => switch (kind) {
        PaycheckEvidenceKind.payslip => Icons.description_outlined,
        PaycheckEvidenceKind.receipt => Icons.receipt_long_outlined,
        PaycheckEvidenceKind.salaryAlert => Icons.sms_outlined,
        PaycheckEvidenceKind.document => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents =
        ref.watch(taxDocumentProvider).asData?.value ?? const <TaxDocument>[];
    final documentsById = {
      for (final document in documents) document.id: document
    };
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
            (item) {
              final document = documentsById[item.id];
              final reviewDocument = document != null &&
                      document.documentType == 'payslip' &&
                      document.needsConfirmation &&
                      document.extractedFields.isNotEmpty
                  ? document
                  : null;
              return _DetectedDocument(
                icon: _iconFor(item.kind),
                title: item.name,
                detail: item.detail,
                badge: item.statusLabel,
                attention: item.needsAction,
                onTap: reviewDocument != null
                    ? () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => _PayslipReviewSheet(
                            document: reviewDocument,
                          ),
                        )
                    : null,
              );
            },
          ),
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
  const _PayslipReviewSheet({required this.document});

  final TaxDocument document;

  @override
  ConsumerState<_PayslipReviewSheet> createState() =>
      _PayslipReviewSheetState();
}

class _PayslipReviewSheetState extends ConsumerState<_PayslipReviewSheet> {
  bool _confirming = false;
  String? _error;

  Map<String, dynamic> get _fields => widget.document.extractedFields;

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
      await ref
          .read(taxDocumentProvider.notifier)
          .confirmParsedFields(widget.document.id);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Payslip confirmed. Home is updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = 'Could not confirm these fields. Try again.';
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
                  Text('Review payslip', style: PaycheckType.title()),
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
                  const _PayslipSectionTitle('Earnings'),
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
                  const _PayslipSectionTitle('Deductions'),
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
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _confirming ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: PaycheckColors.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _confirming ? 'Saving...' : 'Use these payslip details',
                    style: PaycheckType.bodyStrong(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayslipSectionTitle extends StatelessWidget {
  const _PayslipSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title.toUpperCase(), style: PaycheckType.utility()),
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

class _TopBar extends StatelessWidget {
  final String period;
  final bool sample;

  const _TopBar({required this.period, required this.sample});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArthBrandMark(
          size: 30,
          spacing: 9,
          wordmarkStyle: PaycheckType.heading(),
        ),
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
    final canCompare = paycheck.promisedMonthly > 0;
    final period = paycheck.payPeriod == 'No payslip confirmed'
        ? 'PAYCHECK'
        : paycheck.payPeriod.toUpperCase();
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
                  canCompare ? '$period RECONCILIATION' : '$period PAYSLIP',
                  style: PaycheckType.utility(),
                ),
              ),
              const SizedBox(width: 8),
              if (canCompare)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          if (canCompare)
            _RailRow(
              color: PaycheckColors.contract,
              label: 'Promised',
              value: _money(paycheck.promisedMonthly),
              detail: 'Confirmed offer letter',
              isFirst: true,
            ),
          _RailRow(
            color: PaycheckColors.matched,
            label: 'Gross earnings',
            value: _money(paycheck.grossReceived),
            detail: 'Confirmed payslip',
            isFirst: !canCompare,
          ),
          if (paycheck.claimableNow > 0)
            _RailRow(
              color: PaycheckColors.claim,
              label: 'Still claimable',
              value: _money(paycheck.claimableNow),
              detail: 'Benefits with matching proof',
              isLast: true,
            )
          else
            _RailRow(
              color: PaycheckColors.inkSoft,
              label: 'Net pay',
              value: _money(paycheck.netCredited),
              detail: 'After payslip deductions',
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
                  'After your next salary credit',
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
          Text('NEXT MONTH', style: PaycheckType.utility()),
        ],
      ),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArthBrandMark(
              size: 30,
              spacing: 9,
              wordmarkStyle: PaycheckType.heading(),
            ),
            const SizedBox(height: 34),
            Text(eyebrow, style: PaycheckType.utility()),
            const SizedBox(height: 7),
            Text(title, style: PaycheckType.title()),
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
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
