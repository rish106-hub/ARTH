import '../models/money_signal_models.dart';
import '../models/paycheck.dart';
import '../models/user_profile.dart';

class MoneySignalEngine {
  const MoneySignalEngine._();

  static IncomeSignal resolveIncome({
    required int? editedMonthlyIncome,
    required int confirmedPayslipNet,
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
    if (classifications.any(
      (value) => value.contains('nps') || value.contains('80ccd'),
    )) {
      hints.add(
        const PaycheckTaxHint(
          id: 'nps-80ccd',
          title: 'NPS deduction found',
          detail:
              'NPS uses 80CCD rules, not the general 80C bucket. Confirm whether this is employee or employer contribution.',
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
