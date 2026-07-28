enum IncomeSignalSource {
  edited,
  payslip,
  payslipGross,
  salarySms,
  ctcEstimate,
  missing;

  String get label => switch (this) {
        IncomeSignalSource.edited => 'Edited by you',
        IncomeSignalSource.payslip => 'Confirmed payslip net',
        IncomeSignalSource.payslipGross => 'Confirmed payslip gross',
        IncomeSignalSource.salarySms => 'Trusted salary SMS',
        IncomeSignalSource.ctcEstimate => 'CTC estimate',
        IncomeSignalSource.missing => 'Income not set',
      };
}

class IncomeSignal {
  const IncomeSignal({
    required this.primaryMonthlyIncome,
    required this.otherMonthlyIncome,
    required this.source,
  });

  final int primaryMonthlyIncome;
  final int otherMonthlyIncome;
  final IncomeSignalSource source;

  int get monthlyIncome => primaryMonthlyIncome + otherMonthlyIncome;
  bool get isEdited => source == IncomeSignalSource.edited;
  bool get hasIncome => monthlyIncome > 0;

  String get sourceLabel =>
      otherMonthlyIncome > 0 ? '${source.label} + other income' : source.label;
}

enum TdsPaceStatus {
  calculating,
  unavailable,
  aligned,
  over,
  under,
  unknown;

  String get label => switch (this) {
        TdsPaceStatus.calculating => 'CALCULATING',
        TdsPaceStatus.unavailable => 'ESTIMATE UNAVAILABLE',
        TdsPaceStatus.aligned => 'ON PACE',
        TdsPaceStatus.over => 'REVIEW HIGH TDS',
        TdsPaceStatus.under => 'REVIEW LOW TDS',
        TdsPaceStatus.unknown => 'NEEDS PAYSLIP',
      };
}

class PaycheckTaxImpact {
  const PaycheckTaxImpact({
    required this.expectedMonthlyTds,
    required this.actualMonthlyTds,
    required this.status,
    required this.regimeLabel,
  });

  final int expectedMonthlyTds;
  final int actualMonthlyTds;
  final TdsPaceStatus status;
  final String regimeLabel;

  int get difference => actualMonthlyTds - expectedMonthlyTds;
  bool get needsReview =>
      status == TdsPaceStatus.over || status == TdsPaceStatus.under;
}

enum TaxHintKind {
  section80C,
  hra,
  nps,
  professionalTax,
  employerClaim;

  String get label => switch (this) {
        TaxHintKind.section80C => '80C',
        TaxHintKind.hra => 'HRA',
        TaxHintKind.nps => 'NPS',
        TaxHintKind.professionalTax => 'OLD REGIME',
        TaxHintKind.employerClaim => 'EMPLOYER CLAIM',
      };
}

class PaycheckTaxHint {
  const PaycheckTaxHint({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
  });

  final String id;
  final String title;
  final String detail;
  final TaxHintKind kind;
}
