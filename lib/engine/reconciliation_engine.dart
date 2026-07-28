import '../models/paycheck.dart';
import '../models/spend_map.dart';
import '../models/tax_document.dart';

/// Snapshot of the most recent salary credit detected in on-device SMS.
class SalarySmsSnapshot {
  const SalarySmsSnapshot({
    this.latestCreditAmount = 0,
    this.latestCreditDate,
    this.monthlyAverage = 0,
  });

  final int latestCreditAmount;
  final DateTime? latestCreditDate;
  final int monthlyAverage;

  bool get isDetected => latestCreditAmount > 0;

  @override
  bool operator ==(Object other) {
    return other is SalarySmsSnapshot &&
        latestCreditAmount == other.latestCreditAmount &&
        latestCreditDate == other.latestCreditDate &&
        monthlyAverage == other.monthlyAverage;
  }

  @override
  int get hashCode =>
      Object.hash(latestCreditAmount, latestCreditDate, monthlyAverage);
}

/// Parsed document context fed into deterministic reconciliation.
class ReconciliationInput {
  const ReconciliationInput({
    this.offerFields = const {},
    this.payslipFields = const {},
    this.components = const [],
    this.evidence = const [],
    this.salarySms = const SalarySmsSnapshot(),
    this.employeeName = 'Your pay profile',
    this.employer = '',
    this.role = 'Add an offer letter to compare pay',
    this.payPeriod = 'Not connected',
    this.offerLetterAdded = false,
  });

  final Map<String, dynamic> offerFields;
  final Map<String, dynamic> payslipFields;
  final List<PaycheckComponent> components;
  final List<PaycheckEvidence> evidence;
  final SalarySmsSnapshot salarySms;
  final String employeeName;
  final String employer;
  final String role;
  final String payPeriod;
  final bool offerLetterAdded;
}

/// Deterministic offer ↔ payslip ↔ SMS reconciliation. AI does not participate.
class ReconciliationEngine {
  static const _amountTolerance = 1;

  static ReconciliationOutput reconcile(ReconciliationInput input) {
    final earnings = input.components
        .where((c) => c.kind == PaycheckComponentKind.earning)
        .toList();
    final deductions = input.components
        .where((c) => c.kind == PaycheckComponentKind.deduction)
        .toList();

    final gross = earnings.fold<int>(0, (sum, c) => sum + c.amount);
    final totalDeductions = deductions.fold<int>(0, (sum, c) => sum + c.amount);
    final payslipNet = _amount(input.payslipFields['netSalary']) ??
        (gross > 0 ? (gross - totalDeductions).clamp(0, gross) : 0);
    final incomeTax = deductions
        .where((c) => c.classification == 'income_tax')
        .fold<int>(0, (sum, c) => sum + c.amount);

    final promisedLines = _promisedLines(input.offerFields);
    final promisedMonthly = promisedLines.fold<int>(
      0,
      (sum, line) => sum + line.monthlyAmount,
    );
    final annualBenefits = promisedLines
        .where((line) => line.isBenefit)
        .fold<int>(0, (sum, line) => sum + line.annualAmount);

    final items = <PaycheckItem>[];
    final matchedKeys = <String>{};

    for (final line in promisedLines) {
      final payslipMatch = _findPayslipMatch(line, earnings);
      if (payslipMatch != null) {
        matchedKeys.add(payslipMatch.canonicalKey);
        final delta = payslipMatch.amount - line.monthlyAmount;
        if (_withinTolerance(delta)) {
          items.add(
            PaycheckItem(
              id: 'promised-${line.id}',
              label: line.label,
              detail: 'Matched to confirmed payslip',
              amount: payslipMatch.amount,
              status: PaycheckItemStatus.matched,
            ),
          );
        } else {
          items.add(
            PaycheckItem(
              id: 'promised-${line.id}',
              label: line.label,
              detail:
                  'Offer promised ${_money(line.monthlyAmount)}; payslip shows ${_money(payslipMatch.amount)}',
              amount: delta.abs(),
              status: PaycheckItemStatus.review,
              dueLabel: 'Check with HR',
            ),
          );
        }
        continue;
      }

      if (line.classification == 'variable_pay' ||
          line.frequency == 'quarterly' ||
          line.frequency == 'one_time') {
        items.add(
          PaycheckItem(
            id: 'promised-${line.id}',
            label: line.label,
            detail: line.frequency == 'quarterly'
                ? 'Expected in a future payroll cycle'
                : 'Not seen on the latest payslip yet',
            amount: line.monthlyAmount > 0
                ? line.monthlyAmount
                : (line.annualAmount / 12).round(),
            status: PaycheckItemStatus.pending,
            dueLabel: line.frequency == 'quarterly'
                ? 'Quarterly component'
                : 'Awaiting payroll',
          ),
        );
        continue;
      }

      if (line.isBenefit && _hasReceiptEvidence(line, input.evidence)) {
        items.add(
          PaycheckItem(
            id: 'promised-${line.id}',
            label: line.label,
            detail: 'Receipt found — not yet reflected on payslip',
            amount: line.monthlyAmount > 0
                ? line.monthlyAmount
                : (line.annualAmount / 12).round(),
            status: PaycheckItemStatus.claimable,
            dueLabel: 'Prepare claim',
          ),
        );
        continue;
      }

      if (line.isBenefit) {
        items.add(
          PaycheckItem(
            id: 'promised-${line.id}',
            label: line.label,
            detail: 'Benefit in offer letter — add a bill to claim',
            amount: line.monthlyAmount > 0
                ? line.monthlyAmount
                : (line.annualAmount / 12).round(),
            status: PaycheckItemStatus.pending,
            dueLabel: 'Add receipt',
          ),
        );
        continue;
      }

      if (input.offerLetterAdded && line.monthlyAmount > 0) {
        items.add(
          PaycheckItem(
            id: 'promised-${line.id}',
            label: line.label,
            detail: 'Promised in offer letter but missing from payslip',
            amount: line.monthlyAmount,
            status: PaycheckItemStatus.review,
            dueLabel: 'Check with HR',
          ),
        );
      }
    }

    for (final component in earnings) {
      if (matchedKeys.contains(component.canonicalKey)) continue;
      items.add(
        PaycheckItem(
          id: 'earning-${component.canonicalKey}',
          label: component.label,
          detail: input.offerLetterAdded
              ? 'On payslip — not listed in offer letter'
              : 'Recorded from confirmed payslip',
          amount: component.amount,
          status: PaycheckItemStatus.matched,
        ),
      );
    }

    for (final component in deductions) {
      final needsReview = component.classification == 'employee_pf' ||
          component.classification == 'insurance';
      items.add(
        PaycheckItem(
          id: 'deduction-${component.canonicalKey}',
          label: component.label,
          detail: needsReview
              ? 'Verify this deduction reached the right account'
              : 'Deducted in the confirmed payslip',
          amount: component.amount,
          status: needsReview
              ? PaycheckItemStatus.review
              : PaycheckItemStatus.deduction,
          dueLabel: needsReview ? 'Verify deposit' : null,
        ),
      );
    }

    var netCredited = payslipNet;
    if (input.salarySms.isDetected) {
      if (payslipNet > 0 &&
          !_withinTolerance(input.salarySms.latestCreditAmount - payslipNet)) {
        items.add(
          PaycheckItem(
            id: 'salary-sms-vs-payslip',
            label: 'Salary credit vs payslip net',
            detail:
                'SMS credit ${_money(input.salarySms.latestCreditAmount)}; payslip net ${_money(payslipNet)}',
            amount: (input.salarySms.latestCreditAmount - payslipNet).abs(),
            status: PaycheckItemStatus.review,
            dueLabel: 'Confirm which figure is correct',
          ),
        );
      } else if (payslipNet <= 0) {
        netCredited = input.salarySms.latestCreditAmount;
      }
    }

    final claimableNow = items
        .where((item) => item.status == PaycheckItemStatus.claimable)
        .fold<int>(0, (sum, item) => sum + item.amount);

    final sources = <PaycheckSource>[
      if (input.offerLetterAdded)
        const PaycheckSource(
          name: 'Offer letter',
          detail: 'Confirmed compensation promise',
          connected: true,
        ),
      if (gross > 0 || payslipNet > 0)
        const PaycheckSource(
          name: 'Latest payslip',
          detail: 'Confirmed monthly pay',
          connected: true,
        ),
      if (input.salarySms.isDetected)
        PaycheckSource(
          name: 'Salary SMS',
          detail: input.salarySms.latestCreditDate == null
              ? 'Net salary credit detected'
              : 'Last credit ${_formatDate(input.salarySms.latestCreditDate!)}',
          connected: true,
          lastSeen: input.salarySms.latestCreditDate,
        ),
    ];

    return ReconciliationOutput(
      employeeName: input.employeeName,
      employer: input.employer,
      role: input.role,
      payPeriod: input.payPeriod,
      promisedMonthly: promisedMonthly,
      grossReceived: gross,
      netCredited: netCredited,
      claimableNow: claimableNow,
      taxWithheld: incomeTax,
      otherDeductions: (totalDeductions - incomeTax).clamp(0, totalDeductions),
      annualBenefits: annualBenefits,
      offerLetterAdded: input.offerLetterAdded,
      items: items,
      components: input.components,
      sources: sources,
      evidence: input.evidence,
      salarySmsCredited: input.salarySms.latestCreditAmount,
      salarySmsLastSeen: input.salarySms.latestCreditDate,
      salarySmsConnected: input.salarySms.isDetected,
    );
  }

  static List<_PromisedLine> _promisedLines(Map<String, dynamic> offer) {
    final lines = <_PromisedLine>[];
    final components = _rows(offer['components']);
    for (final row in components) {
      final annual = _amount(row['annualAmount']);
      if (annual == null || annual <= 0) continue;
      final frequency = row['frequency']?.toString() ?? 'unknown';
      final classification = row['classification']?.toString() ?? 'other';
      lines.add(
        _PromisedLine(
          id: _itemId(row['label']),
          label: row['label']?.toString() ?? 'Component',
          classification: classification,
          frequency: frequency,
          annualAmount: annual,
          monthlyAmount: _monthlyFromAnnual(annual, frequency),
          isBenefit: classification == 'reimbursement' ||
              classification == 'allowance',
        ),
      );
    }

    if (lines.isEmpty) {
      final fixedAnnual = _amount(offer['fixedAnnualPay']);
      if (fixedAnnual != null && fixedAnnual > 0) {
        lines.add(
          _PromisedLine(
            id: 'fixed-pay',
            label: 'Fixed pay',
            classification: 'fixed_pay',
            frequency: 'monthly',
            annualAmount: fixedAnnual,
            monthlyAmount: (fixedAnnual / 12).round(),
            isBenefit: false,
          ),
        );
      }
      final variableAnnual = _amount(offer['variableAnnualPay']);
      if (variableAnnual != null && variableAnnual > 0) {
        lines.add(
          _PromisedLine(
            id: 'variable-pay',
            label: 'Variable pay',
            classification: 'variable_pay',
            frequency: 'quarterly',
            annualAmount: variableAnnual,
            monthlyAmount: (variableAnnual / 12).round(),
            isBenefit: false,
          ),
        );
      }
    }

    return lines;
  }

  static PaycheckComponent? _findPayslipMatch(
    _PromisedLine line,
    List<PaycheckComponent> earnings,
  ) {
    PaycheckComponent? best;
    var bestScore = 0;
    for (final earning in earnings) {
      final score = _matchScore(line, earning);
      if (score > bestScore) {
        bestScore = score;
        best = earning;
      }
    }
    return bestScore >= 2 ? best : null;
  }

  static int _matchScore(_PromisedLine line, PaycheckComponent earning) {
    var score = 0;
    if (line.classification == earning.classification) score += 3;
    if (_classificationsRelated(line.classification, earning.classification)) {
      score += 2;
    }
    if (_labelsOverlap(line.label, earning.label)) score += 2;
    if (_withinTolerance(earning.amount - line.monthlyAmount)) score += 1;
    return score;
  }

  static bool _classificationsRelated(String left, String right) {
    if (left == right) return true;
    const hraFamily = {'allowance', 'hra'};
    if (hraFamily.contains(left) && hraFamily.contains(right)) return true;
    const fixedFamily = {'fixed_pay', 'basic_pay'};
    if (fixedFamily.contains(left) && fixedFamily.contains(right)) return true;
    return false;
  }

  static bool _labelsOverlap(String a, String b) {
    final left = a.toLowerCase();
    final right = b.toLowerCase();
    if (left.contains(right) || right.contains(left)) return true;
    final leftTokens =
        left.split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 2);
    final rightTokens =
        right.split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 2);
    return leftTokens.any(rightTokens.contains);
  }

  static bool _hasReceiptEvidence(
    _PromisedLine line,
    List<PaycheckEvidence> evidence,
  ) {
    final keywords = _benefitKeywords(line.label);
    for (final item in evidence) {
      if (item.kind != PaycheckEvidenceKind.receipt &&
          item.kind != PaycheckEvidenceKind.document) {
        continue;
      }
      final haystack = '${item.name} ${item.detail}'.toLowerCase();
      if (keywords.any(haystack.contains)) return true;
      if (item.kind == PaycheckEvidenceKind.receipt) return true;
    }
    return false;
  }

  static List<String> _benefitKeywords(String label) {
    final lower = label.toLowerCase();
    const known = [
      'internet',
      'broadband',
      'wellness',
      'gym',
      'food',
      'meal',
      'travel',
      'lta',
      'phone',
      'mobile',
      'fuel',
      'cab',
    ];
    return known.where(lower.contains).toList();
  }

  static int _monthlyFromAnnual(int annual, String frequency) =>
      switch (frequency) {
        'monthly' => (annual / 12).round(),
        'quarterly' => (annual / 12).round(),
        'annual' => (annual / 12).round(),
        'one_time' => annual,
        _ => (annual / 12).round(),
      };

  static bool _withinTolerance(int delta) => delta.abs() <= _amountTolerance;

  static List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  static int? _amount(Object? value) => value is num ? value.round() : null;

  static String _itemId(Object? value) => (value?.toString() ?? 'item')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static String _money(int amount) => '₹$amount';

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

class ReconciliationOutput {
  const ReconciliationOutput({
    required this.employeeName,
    required this.employer,
    required this.role,
    required this.payPeriod,
    required this.promisedMonthly,
    required this.grossReceived,
    required this.netCredited,
    required this.claimableNow,
    required this.taxWithheld,
    required this.otherDeductions,
    required this.annualBenefits,
    required this.offerLetterAdded,
    required this.items,
    required this.components,
    required this.sources,
    required this.evidence,
    required this.salarySmsCredited,
    required this.salarySmsLastSeen,
    required this.salarySmsConnected,
  });

  final String employeeName;
  final String employer;
  final String role;
  final String payPeriod;
  final int promisedMonthly;
  final int grossReceived;
  final int netCredited;
  final int claimableNow;
  final int taxWithheld;
  final int otherDeductions;
  final int annualBenefits;
  final bool offerLetterAdded;
  final List<PaycheckItem> items;
  final List<PaycheckComponent> components;
  final List<PaycheckSource> sources;
  final List<PaycheckEvidence> evidence;
  final int salarySmsCredited;
  final DateTime? salarySmsLastSeen;
  final bool salarySmsConnected;

  PaycheckState toPaycheckState({
    required Set<String> preparedClaims,
    bool usingSampleData = false,
    bool inboxConnected = false,
  }) {
    return PaycheckState(
      employeeName: employeeName,
      employer: employer,
      role: role,
      payPeriod: payPeriod,
      promisedMonthly: promisedMonthly,
      grossReceived: grossReceived,
      netCredited: netCredited,
      claimableNow: claimableNow,
      taxWithheld: taxWithheld,
      otherDeductions: otherDeductions,
      annualBenefits: annualBenefits,
      usingSampleData: usingSampleData,
      offerLetterAdded: offerLetterAdded,
      inboxConnected: inboxConnected,
      preparedClaims: preparedClaims,
      items: items,
      components: components,
      sources: sources,
      evidence: evidence,
      salarySmsCredited: salarySmsCredited,
      salarySmsLastSeen: salarySmsLastSeen,
      salarySmsConnected: salarySmsConnected,
    );
  }
}

class _PromisedLine {
  const _PromisedLine({
    required this.id,
    required this.label,
    required this.classification,
    required this.frequency,
    required this.annualAmount,
    required this.monthlyAmount,
    required this.isBenefit,
  });

  final String id;
  final String label;
  final String classification;
  final String frequency;
  final int annualAmount;
  final int monthlyAmount;
  final bool isBenefit;
}

/// Builds a [SalarySmsSnapshot] from a spend map.
SalarySmsSnapshot salarySmsFromSpendMap(SpendMap map) {
  final salaries = map.trustedSalaryTransactions.toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  if (salaries.isEmpty) {
    return const SalarySmsSnapshot();
  }

  final latest = salaries.first;
  final salaryMonths = salaries
      .map((txn) => DateTime(txn.date.year, txn.date.month))
      .toSet()
      .length;
  return SalarySmsSnapshot(
    latestCreditAmount: latest.amount,
    latestCreditDate: latest.date,
    monthlyAverage:
        salaryMonths > 0 ? (map.salaryCredited / salaryMonths).round() : 0,
  );
}

/// Marks receipt-like evidence from uploaded documents.
PaycheckEvidenceKind evidenceKindForDocument(TaxDocument document) {
  final lower = document.originalFilename.toLowerCase();
  final receiptLike = lower.contains('receipt') ||
      lower.contains('bill') ||
      lower.contains('gym') ||
      lower.contains('invoice');
  if (receiptLike) return PaycheckEvidenceKind.receipt;
  if (document.isPayslip) return PaycheckEvidenceKind.payslip;
  return PaycheckEvidenceKind.document;
}
