import 'package:arth/engine/money_signal_engine.dart';
import 'package:arth/models/money_signal_models.dart';
import 'package:arth/models/paycheck.dart';
import 'package:arth/models/spend_map.dart';
import 'package:arth/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('income signal', () {
    test('manual income wins and keeps other income separate', () {
      final signal = MoneySignalEngine.resolveIncome(
        editedMonthlyIncome: 90000,
        confirmedPayslipNet: 80000,
        trustedSalarySmsMonthly: 70000,
        annualCtc: 720000,
        otherMonthlyIncome: 12000,
      );

      expect(signal.primaryMonthlyIncome, 90000);
      expect(signal.otherMonthlyIncome, 12000);
      expect(signal.monthlyIncome, 102000);
      expect(signal.source, IncomeSignalSource.edited);
      expect(signal.sourceLabel, 'Edited by you + other income');
    });

    test('uses payslip, salary SMS, then CTC in that order', () {
      final payslip = MoneySignalEngine.resolveIncome(
        editedMonthlyIncome: null,
        confirmedPayslipNet: 80000,
        trustedSalarySmsMonthly: 70000,
        annualCtc: 720000,
        otherMonthlyIncome: 0,
      );
      final sms = MoneySignalEngine.resolveIncome(
        editedMonthlyIncome: null,
        confirmedPayslipNet: 0,
        trustedSalarySmsMonthly: 70000,
        annualCtc: 720000,
        otherMonthlyIncome: 0,
      );
      final ctc = MoneySignalEngine.resolveIncome(
        editedMonthlyIncome: null,
        confirmedPayslipNet: 0,
        trustedSalarySmsMonthly: 0,
        annualCtc: 720000,
        otherMonthlyIncome: 0,
      );

      expect(payslip.source, IncomeSignalSource.payslip);
      expect(payslip.primaryMonthlyIncome, 80000);
      expect(sms.source, IncomeSignalSource.salarySms);
      expect(sms.primaryMonthlyIncome, 70000);
      expect(ctc.source, IncomeSignalSource.ctcEstimate);
      expect(ctc.primaryMonthlyIncome, 60000);
    });

    test('Spend map uses the same resolved source as Home and Goal', () {
      final map = SpendMap(
        txns: [
          FinanceTxn(
            amount: 70000,
            direction: TxnDirection.credit,
            date: DateTime(2026, 7, 1),
            category: SpendCategory.other,
            isSalary: true,
          ),
        ],
        windowStart: DateTime(2026, 7),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      const payslipSignal = IncomeSignal(
        primaryMonthlyIncome: 80000,
        otherMonthlyIncome: 12000,
        source: IncomeSignalSource.payslip,
      );

      final resolved = map.withIncomeSignal(payslipSignal);

      expect(resolved.monthlyIncome, 92000);
      expect(resolved.primaryIncomeSourceLabel, 'Confirmed payslip net');
      expect(resolved.incomeIsDetected, isFalse);
    });
  });

  group('paycheck tax impact', () {
    test('classifies TDS pace with a ten percent tolerance', () {
      final aligned = MoneySignalEngine.taxImpact(
        actualMonthlyTds: 10000,
        expectedAnnualTax: 120000,
        regimeLabel: 'new regime',
        hasConfirmedPayslip: true,
      );
      final over = MoneySignalEngine.taxImpact(
        actualMonthlyTds: 13000,
        expectedAnnualTax: 120000,
        regimeLabel: 'new regime',
        hasConfirmedPayslip: true,
      );
      final under = MoneySignalEngine.taxImpact(
        actualMonthlyTds: 7000,
        expectedAnnualTax: 120000,
        regimeLabel: 'new regime',
        hasConfirmedPayslip: true,
      );
      final unknown = MoneySignalEngine.taxImpact(
        actualMonthlyTds: 0,
        expectedAnnualTax: 120000,
        regimeLabel: 'new regime',
        hasConfirmedPayslip: false,
      );

      expect(aligned.status, TdsPaceStatus.aligned);
      expect(over.status, TdsPaceStatus.over);
      expect(under.status, TdsPaceStatus.under);
      expect(unknown.status, TdsPaceStatus.unknown);
    });

    test('flags TDS when expected annual tax is zero', () {
      final impact = MoneySignalEngine.taxImpact(
        actualMonthlyTds: 900,
        expectedAnnualTax: 0,
        regimeLabel: 'new regime',
        hasConfirmedPayslip: true,
      );

      expect(impact.status, TdsPaceStatus.over);
      expect(impact.expectedMonthlyTds, 0);
    });
  });

  test('tax hints stay inside payslip evidence and employer policy', () {
    final paycheck = emptyPaycheck.copyWith(
      components: const [
        PaycheckComponent(
          label: 'HRA',
          canonicalKey: 'hra',
          classification: 'hra',
          amount: 12000,
          kind: PaycheckComponentKind.earning,
        ),
        PaycheckComponent(
          label: 'PF',
          canonicalKey: 'employee_pf',
          classification: 'employee_pf',
          amount: 3000,
          kind: PaycheckComponentKind.deduction,
        ),
        PaycheckComponent(
          label: 'NPS',
          canonicalKey: 'nps_80ccd_1b',
          classification: 'nps_80ccd_1b',
          amount: 2000,
          kind: PaycheckComponentKind.deduction,
        ),
        PaycheckComponent(
          label: 'Professional tax',
          canonicalKey: 'professional_tax',
          classification: 'professional_tax',
          amount: 200,
          kind: PaycheckComponentKind.deduction,
        ),
      ],
      items: const [
        PaycheckItem(
          id: 'internet',
          label: 'Internet reimbursement',
          detail: 'Submit to employer',
          amount: 1200,
          status: PaycheckItemStatus.claimable,
        ),
      ],
    );

    final hints = MoneySignalEngine.taxHints(
      paycheck,
      const UserProfile(paysRent: true),
    );

    expect(
      hints.map((hint) => hint.kind),
      containsAll(TaxHintKind.values),
    );
    expect(
      hints.last.detail,
      contains('does not label reimbursements as 80C'),
    );
  });
}
