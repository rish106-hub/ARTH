enum PaycheckItemStatus { matched, claimable, pending, deduction, review }

enum PaycheckComponentKind { earning, deduction }

class PaycheckComponent {
  final String label;
  final String canonicalKey;
  final String classification;
  final int amount;
  final PaycheckComponentKind kind;

  const PaycheckComponent({
    required this.label,
    required this.canonicalKey,
    required this.classification,
    required this.amount,
    required this.kind,
  });
}

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
  final List<PaycheckComponent> components;
  final List<PaycheckSource> sources;
  final List<PaycheckEvidence> evidence;
  final int salarySmsCredited;
  final DateTime? salarySmsLastSeen;
  final bool salarySmsConnected;

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
    required this.components,
    required this.sources,
    required this.evidence,
    this.salarySmsCredited = 0,
    this.salarySmsLastSeen,
    this.salarySmsConnected = false,
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
    String? employeeName,
    String? employer,
    String? role,
    String? payPeriod,
    int? promisedMonthly,
    int? grossReceived,
    int? netCredited,
    int? claimableNow,
    int? taxWithheld,
    int? otherDeductions,
    int? annualBenefits,
    bool? usingSampleData,
    bool? offerLetterAdded,
    bool? inboxConnected,
    Set<String>? preparedClaims,
    List<PaycheckItem>? items,
    List<PaycheckComponent>? components,
    List<PaycheckSource>? sources,
    List<PaycheckEvidence>? evidence,
    int? salarySmsCredited,
    DateTime? salarySmsLastSeen,
    bool? salarySmsConnected,
  }) {
    return PaycheckState(
      employeeName: employeeName ?? this.employeeName,
      employer: employer ?? this.employer,
      role: role ?? this.role,
      payPeriod: payPeriod ?? this.payPeriod,
      promisedMonthly: promisedMonthly ?? this.promisedMonthly,
      grossReceived: grossReceived ?? this.grossReceived,
      netCredited: netCredited ?? this.netCredited,
      claimableNow: claimableNow ?? this.claimableNow,
      taxWithheld: taxWithheld ?? this.taxWithheld,
      otherDeductions: otherDeductions ?? this.otherDeductions,
      annualBenefits: annualBenefits ?? this.annualBenefits,
      usingSampleData: usingSampleData ?? this.usingSampleData,
      offerLetterAdded: offerLetterAdded ?? this.offerLetterAdded,
      inboxConnected: inboxConnected ?? this.inboxConnected,
      preparedClaims: preparedClaims ?? this.preparedClaims,
      items: items ?? this.items,
      components: components ?? this.components,
      sources: sources ?? this.sources,
      evidence: evidence ?? this.evidence,
      salarySmsCredited: salarySmsCredited ?? this.salarySmsCredited,
      salarySmsLastSeen: salarySmsLastSeen ?? this.salarySmsLastSeen,
      salarySmsConnected: salarySmsConnected ?? this.salarySmsConnected,
    );
  }
}

const emptyPaycheck = PaycheckState(
  employeeName: 'Your pay profile',
  employer: '',
  role: 'Add an offer letter to begin',
  payPeriod: 'Not connected',
  promisedMonthly: 0,
  grossReceived: 0,
  netCredited: 0,
  claimableNow: 0,
  taxWithheld: 0,
  otherDeductions: 0,
  annualBenefits: 0,
  usingSampleData: false,
  offerLetterAdded: false,
  inboxConnected: false,
  preparedClaims: {},
  items: [],
  components: [],
  sources: [],
  evidence: [],
  salarySmsCredited: 0,
  salarySmsConnected: false,
);

final demoPaycheck = PaycheckState(
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
    const PaycheckItem(
      id: 'fixed-pay',
      label: 'Fixed pay',
      detail: 'Matched to July payslip',
      amount: 45000,
      status: PaycheckItemStatus.matched,
    ),
    const PaycheckItem(
      id: 'internet',
      label: 'Internet reimbursement',
      detail: 'Bill found in your inbox',
      amount: 1200,
      status: PaycheckItemStatus.claimable,
      dueLabel: 'Claim by 31 Jul',
    ),
    const PaycheckItem(
      id: 'wellness',
      label: 'Wellness allowance',
      detail: '₹20,000 annual allowance',
      amount: 5200,
      status: PaycheckItemStatus.claimable,
      dueLabel: '₹5,200 available now',
    ),
    const PaycheckItem(
      id: 'variable',
      label: 'Quarterly variable pay',
      detail: 'Expected with September payroll',
      amount: 7500,
      status: PaycheckItemStatus.pending,
      dueLabel: 'Due in 62 days',
    ),
    const PaycheckItem(
      id: 'tds',
      label: 'Tax withheld',
      detail: 'Recorded from payslip',
      amount: 3260,
      status: PaycheckItemStatus.deduction,
    ),
    const PaycheckItem(
      id: 'pf',
      label: 'Provident fund',
      detail: 'Employee and employer contribution',
      amount: 3520,
      status: PaycheckItemStatus.review,
      dueLabel: 'Verify deposit',
    ),
  ],
  components: [
    const PaycheckComponent(
      label: 'Basic pay',
      canonicalKey: 'basic_pay',
      classification: 'basic_pay',
      amount: 45000,
      kind: PaycheckComponentKind.earning,
    ),
    const PaycheckComponent(
      label: 'House rent allowance',
      canonicalKey: 'house_rent_allowance',
      classification: 'hra',
      amount: 5200,
      kind: PaycheckComponentKind.earning,
    ),
    const PaycheckComponent(
      label: 'Performance pay',
      canonicalKey: 'performance_pay',
      classification: 'variable_pay',
      amount: 2500,
      kind: PaycheckComponentKind.earning,
    ),
    const PaycheckComponent(
      label: 'Income tax',
      canonicalKey: 'income_tax',
      classification: 'income_tax',
      amount: 3260,
      kind: PaycheckComponentKind.deduction,
    ),
    const PaycheckComponent(
      label: 'Provident fund',
      canonicalKey: 'employee_provident_fund',
      classification: 'employee_pf',
      amount: 3520,
      kind: PaycheckComponentKind.deduction,
    ),
  ],
  sources: [
    const PaycheckSource(
      name: 'Offer letter',
      detail: 'Compensation promise',
      connected: true,
    ),
    const PaycheckSource(
      name: 'Gmail receipts',
      detail: 'Payslips and eligible bills',
      connected: true,
    ),
    const PaycheckSource(
      name: 'Salary SMS',
      detail: 'Net credit confirmation',
      connected: true,
    ),
  ],
  evidence: [
    const PaycheckEvidence(
      id: 'july-payslip',
      name: 'July payslip',
      detail: '6 compensation lines extracted',
      statusLabel: 'MATCHED',
      kind: PaycheckEvidenceKind.payslip,
    ),
    const PaycheckEvidence(
      id: 'broadband-bill',
      name: 'Broadband bill',
      detail: 'Eligible for internet reimbursement',
      statusLabel: 'USE NOW',
      kind: PaycheckEvidenceKind.receipt,
      needsAction: true,
    ),
    const PaycheckEvidence(
      id: 'gym-receipt',
      name: 'Gym receipt',
      detail: 'Eligible under wellness allowance',
      statusLabel: 'USE NOW',
      kind: PaycheckEvidenceKind.receipt,
      needsAction: true,
    ),
  ],
  salarySmsCredited: 45920,
  salarySmsLastSeen: DateTime(2026, 7, 1),
  salarySmsConnected: true,
);
