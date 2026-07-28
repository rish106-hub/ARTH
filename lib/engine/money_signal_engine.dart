import '../models/money_signal_models.dart';
import '../models/paycheck.dart';
import '../models/user_profile.dart';

class MoneySignalEngine {
  const MoneySignalEngine._();

  static IncomeSignal resolveIncome({
    required int? editedMonthlyIncome,
    required int confirmedPayslipNet,
    int confirmedPayslipGross = 0,
    required int trustedSalarySmsMonthly,
    required int annualCtc,
    required int otherMonthlyIncome,
  }) {
    if (editedMonthlyIncome != null && editedMonthlyIncome > 0) {
      return IncomeSignal(
        primaryMonthlyIncome: editedMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        source: IncomeSignalSource.edited,
      );
    }
    if (confirmedPayslipNet > 0) {
      return IncomeSignal(
        primaryMonthlyIncome: confirmedPayslipNet,
        otherMonthlyIncome: otherMonthlyIncome,
        source: IncomeSignalSource.payslip,
      );
    }
    if (confirmedPayslipGross > 0) {
      return IncomeSignal(
        primaryMonthlyIncome: confirmedPayslipGross,
        otherMonthlyIncome: otherMonthlyIncome,
        source: IncomeSignalSource.payslipGross,
      );
    }
    if (trustedSalarySmsMonthly > 0) {
      return IncomeSignal(
        primaryMonthlyIncome: trustedSalarySmsMonthly,
        otherMonthlyIncome: otherMonthlyIncome,
        source: IncomeSignalSource.salarySms,
      );
    }
    if (annualCtc > 0) {
      return IncomeSignal(
        primaryMonthlyIncome: (annualCtc / 12).round(),
        otherMonthlyIncome: otherMonthlyIncome,
        source: IncomeSignalSource.ctcEstimate,
      );
    }
    return IncomeSignal(
      primaryMonthlyIncome: 0,
      otherMonthlyIncome: otherMonthlyIncome,
      source: IncomeSignalSource.missing,
    );
  }

  static PaycheckTaxImpact taxImpact({
    required int actualMonthlyTds,
    required int expectedAnnualTax,
    required String regimeLabel,
    required bool hasConfirmedPayslip,
  }) {
    if (!hasConfirmedPayslip) {
      return PaycheckTaxImpact(
        expectedMonthlyTds:
            expectedAnnualTax <= 0 ? 0 : (expectedAnnualTax / 12).round(),
        actualMonthlyTds: actualMonthlyTds,
        status: TdsPaceStatus.unknown,
        regimeLabel: regimeLabel,
      );
    }
    if (expectedAnnualTax <= 0) {
      return PaycheckTaxImpact(
        expectedMonthlyTds: 0,
        actualMonthlyTds: actualMonthlyTds,
        status:
            actualMonthlyTds > 500 ? TdsPaceStatus.over : TdsPaceStatus.aligned,
        regimeLabel: regimeLabel,
      );
    }
    final expected = (expectedAnnualTax / 12).round();
    final tolerance = (expected * 0.10).round().clamp(500, 100000000);
    final difference = actualMonthlyTds - expected;
    final status = difference.abs() <= tolerance
        ? TdsPaceStatus.aligned
        : difference > 0
            ? TdsPaceStatus.over
            : TdsPaceStatus.under;
    return PaycheckTaxImpact(
      expectedMonthlyTds: expected,
      actualMonthlyTds: actualMonthlyTds,
      status: status,
      regimeLabel: regimeLabel,
    );
  }

  static List<PaycheckTaxHint> taxHints(
    PaycheckState paycheck,
    UserProfile profile,
  ) {
    final hints = <PaycheckTaxHint>[];
    final classifications = paycheck.components
        .map((component) => component.classification.toLowerCase())
        .toSet();

    if (classifications.contains('employee_pf') ||
        classifications.contains('voluntary_pf')) {
      hints.add(
        const PaycheckTaxHint(
          id: 'pf-80c',
          title: 'Provident fund found',
          detail:
              'Employee PF can count inside the combined 80C limit. Confirm the annual total before adding other 80C investments.',
          kind: TaxHintKind.section80C,
        ),
      );
    }
    if (classifications.contains('hra') && profile.paysRent) {
      hints.add(
        const PaycheckTaxHint(
          id: 'hra-rent',
          title: 'HRA and rent found',
          detail:
              'HRA exemption needs rent details and is relevant only under the old regime. Keep rent receipts.',
          kind: TaxHintKind.hra,
        ),
      );
    }
    final npsComponents = paycheck.components.where((component) {
      final text =
          '${component.label} ${component.canonicalKey} ${component.classification}'
              .toLowerCase();
      return text.contains('nps') || text.contains('80ccd');
    }).toList(growable: false);
    final hasEmployerNps = npsComponents.any((component) {
      final text =
          '${component.label} ${component.canonicalKey} ${component.classification}'
              .toLowerCase();
      return text.contains('employer') || text.contains('80ccd(2)');
    });
    final hasAdditionalNps = npsComponents.any((component) {
      final text =
          '${component.label} ${component.canonicalKey} ${component.classification}'
              .toLowerCase();
      return text.contains('1b') || text.contains('80ccd(1b)');
    });
    final hasEmployeeNps = npsComponents.any((component) {
      final text =
          '${component.label} ${component.canonicalKey} ${component.classification}'
              .toLowerCase();
      final employer = text.contains('employer') || text.contains('80ccd(2)');
      final additional = text.contains('1b') || text.contains('80ccd(1b)');
      return !employer && !additional;
    });
    if (hasEmployeeNps) {
      hints.add(
        const PaycheckTaxHint(
          id: 'nps-employee',
          title: 'Employee NPS found',
          detail:
              'Employee NPS under 80CCD(1) shares the combined ₹1.5 lakh ceiling with 80C and 80CCC. Confirm the payroll classification.',
          kind: TaxHintKind.nps,
        ),
      );
    }
    if (hasAdditionalNps) {
      hints.add(
        const PaycheckTaxHint(
          id: 'nps-1b',
          title: 'Additional NPS found',
          detail:
              '80CCD(1B) is a separate additional deduction under the old regime. Confirm the annual employee contribution.',
          kind: TaxHintKind.nps,
        ),
      );
    }
    if (hasEmployerNps) {
      hints.add(
        const PaycheckTaxHint(
          id: 'nps-employer',
          title: 'Employer NPS found',
          detail:
              'Employer NPS uses 80CCD(2), separate from the employee 80C ceiling. Confirm how payroll classified it.',
          kind: TaxHintKind.nps,
        ),
      );
    }
    if (classifications.contains('professional_tax')) {
      hints.add(
        const PaycheckTaxHint(
          id: 'professional-tax',
          title: 'Professional tax found',
          detail:
              'Professional tax is deductible from salary under the old regime. ARTH prefills the annualized payslip amount.',
          kind: TaxHintKind.professionalTax,
        ),
      );
    }

    final claimable = paycheck.items.where(
      (item) => item.status == PaycheckItemStatus.claimable,
    );
    if (claimable.isNotEmpty) {
      hints.add(
        PaycheckTaxHint(
          id: 'employer-reimbursements',
          title:
              '${claimable.length} employer claim${claimable.length == 1 ? '' : 's'} found',
          detail:
              'Submit these through employer policy. ARTH does not label reimbursements as 80C deductions.',
          kind: TaxHintKind.employerClaim,
        ),
      );
    }
    return hints;
  }
}
