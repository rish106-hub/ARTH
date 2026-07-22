enum PaycheckItemStatus { matched, claimable, pending, deduction, review }

class PaycheckItem {
  final String id;
  final String label;
  final String detail;
  final int amount;
  final PaycheckItemStatus status;
  final String? dueLabel;

  const PaycheckItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.amount,
    required this.status,
    this.dueLabel,
  });
}

class PaycheckSource {
  final String name;
  final String detail;
  final bool connected;
  final DateTime? lastSeen;

  const PaycheckSource({
    required this.name,
    required this.detail,
    required this.connected,
    this.lastSeen,
  });
}

enum PaycheckEvidenceKind { payslip, receipt, salaryAlert, document }

class PaycheckEvidence {
  final String id;
  final String name;
  final String detail;
  final String statusLabel;
  final PaycheckEvidenceKind kind;
  final bool needsAction;

  const PaycheckEvidence({
    required this.id,
    required this.name,
    required this.detail,
    required this.statusLabel,
    required this.kind,
    this.needsAction = false,
  });
}

class PaycheckState {
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
  final bool usingSampleData;
  final bool offerLetterAdded;
  final bool inboxConnected;
  final Set<String> preparedClaims;
  final List<PaycheckItem> items;
  final List<PaycheckSource> sources;
  final List<PaycheckEvidence> evidence;

  const PaycheckState({
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
    required this.usingSampleData,
    required this.offerLetterAdded,
    required this.inboxConnected,
    required this.preparedClaims,
    required this.items,
    required this.sources,
    required this.evidence,
  });

  int get matchedAmount => items
      .where((item) => item.status == PaycheckItemStatus.matched)
      .fold(0, (sum, item) => sum + item.amount);

  int get pendingAmount => items
      .where((item) => item.status == PaycheckItemStatus.pending)
      .fold(0, (sum, item) => sum + item.amount);

  int get reconciliationPercent {
    if (promisedMonthly <= 0) return 0;
    return ((grossReceived / promisedMonthly) * 100).clamp(0, 100).round();
  }

  PaycheckState copyWith({
    bool? usingSampleData,
    bool? offerLetterAdded,
    bool? inboxConnected,
    Set<String>? preparedClaims,
    List<PaycheckSource>? sources,
    List<PaycheckEvidence>? evidence,
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
      usingSampleData: usingSampleData ?? this.usingSampleData,
      offerLetterAdded: offerLetterAdded ?? this.offerLetterAdded,
      inboxConnected: inboxConnected ?? this.inboxConnected,
      preparedClaims: preparedClaims ?? this.preparedClaims,
      items: items,
      sources: sources ?? this.sources,
      evidence: evidence ?? this.evidence,
    );
  }
}

const demoPaycheck = PaycheckState(
  employeeName: 'Aarav',
  employer: 'Northstar Labs India',
  role: 'Associate Product Analyst',
  payPeriod: 'July 2026',
  promisedMonthly: 54500,
  grossReceived: 52700,
  netCredited: 45920,
  claimableNow: 6400,
  taxWithheld: 3260,
  otherDeductions: 3520,
  annualBenefits: 46800,
  usingSampleData: true,
  offerLetterAdded: true,
  inboxConnected: true,
  preparedClaims: {},
  items: [
    PaycheckItem(
      id: 'fixed-pay',
      label: 'Fixed pay',
      detail: 'Matched to July payslip',
      amount: 45000,
      status: PaycheckItemStatus.matched,
    ),
    PaycheckItem(
      id: 'internet',
      label: 'Internet reimbursement',
      detail: 'Bill found in your inbox',
      amount: 1200,
      status: PaycheckItemStatus.claimable,
      dueLabel: 'Claim by 31 Jul',
    ),
    PaycheckItem(
      id: 'wellness',
      label: 'Wellness allowance',
      detail: '₹20,000 annual allowance',
      amount: 5200,
      status: PaycheckItemStatus.claimable,
      dueLabel: '₹5,200 available now',
    ),
    PaycheckItem(
      id: 'variable',
      label: 'Quarterly variable pay',
      detail: 'Expected with September payroll',
      amount: 7500,
      status: PaycheckItemStatus.pending,
      dueLabel: 'Due in 62 days',
    ),
    PaycheckItem(
      id: 'tds',
      label: 'Tax withheld',
      detail: 'Recorded from payslip',
      amount: 3260,
      status: PaycheckItemStatus.deduction,
    ),
    PaycheckItem(
      id: 'pf',
      label: 'Provident fund',
      detail: 'Employee and employer contribution',
      amount: 3520,
      status: PaycheckItemStatus.review,
      dueLabel: 'Verify deposit',
    ),
  ],
  sources: [
    PaycheckSource(
      name: 'Offer letter',
      detail: 'Compensation promise',
      connected: true,
    ),
    PaycheckSource(
      name: 'Gmail receipts',
      detail: 'Payslips and eligible bills',
      connected: true,
    ),
    PaycheckSource(
      name: 'Salary SMS',
      detail: 'Net credit confirmation',
      connected: true,
    ),
  ],
  evidence: [
    PaycheckEvidence(
      id: 'july-payslip',
      name: 'July payslip',
      detail: '6 compensation lines extracted',
      statusLabel: 'MATCHED',
      kind: PaycheckEvidenceKind.payslip,
    ),
    PaycheckEvidence(
      id: 'broadband-bill',
      name: 'Broadband bill',
      detail: 'Eligible for internet reimbursement',
      statusLabel: 'USE NOW',
      kind: PaycheckEvidenceKind.receipt,
      needsAction: true,
    ),
    PaycheckEvidence(
      id: 'gym-receipt',
      name: 'Gym receipt',
      detail: 'Eligible under wellness allowance',
      statusLabel: 'USE NOW',
      kind: PaycheckEvidenceKind.receipt,
      needsAction: true,
    ),
  ],
);
