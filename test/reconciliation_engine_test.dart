import 'package:arth/engine/reconciliation_engine.dart';
import 'package:arth/models/paycheck.dart';
import 'package:arth/models/spend_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaycheckComponent earning({
    required String label,
    required String key,
    required String classification,
    required int amount,
  }) =>
      PaycheckComponent(
        label: label,
        canonicalKey: key,
        classification: classification,
        amount: amount,
        kind: PaycheckComponentKind.earning,
      );

  PaycheckComponent deduction({
    required String label,
    required String key,
    required String classification,
    required int amount,
  }) =>
      PaycheckComponent(
        label: label,
        canonicalKey: key,
        classification: classification,
        amount: amount,
        kind: PaycheckComponentKind.deduction,
      );

  group('ReconciliationEngine', () {
    test('matches offer fixed pay to payslip basic within tolerance', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          offerFields: const {
            'fixedAnnualPay': 600000,
            'roleTitle': 'Analyst',
          },
          payslipFields: const {'netSalary': 48500},
          components: [
            earning(
              label: 'Basic pay',
              key: 'basic_pay',
              classification: 'basic_pay',
              amount: 50000,
            ),
            deduction(
              label: 'Income tax',
              key: 'income_tax',
              classification: 'income_tax',
              amount: 1500,
            ),
          ],
          offerLetterAdded: true,
          payPeriod: 'July 2026',
        ),
      );

      expect(output.promisedMonthly, 50000);
      expect(output.grossReceived, 50000);
      expect(
        output.items.any(
          (item) =>
              item.status == PaycheckItemStatus.matched &&
              item.label == 'Fixed pay',
        ),
        isTrue,
      );
    });

    test('flags amount mismatch between offer and payslip', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          offerFields: const {
            'components': [
              {
                'label': 'House rent allowance',
                'annualAmount': 240000,
                'frequency': 'monthly',
                'classification': 'allowance',
              },
            ],
          },
          components: [
            earning(
              label: 'HRA',
              key: 'hra',
              classification: 'hra',
              amount: 18000,
            ),
          ],
          offerLetterAdded: true,
        ),
      );

      expect(
        output.items.any(
          (item) =>
              item.label == 'House rent allowance' &&
              item.status == PaycheckItemStatus.review,
        ),
        isTrue,
      );
    });

    test('marks variable pay as pending when absent from payslip', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          offerFields: const {
            'variableAnnualPay': 120000,
          },
          components: [
            earning(
              label: 'Basic',
              key: 'basic',
              classification: 'basic_pay',
              amount: 40000,
            ),
          ],
          offerLetterAdded: true,
        ),
      );

      expect(
        output.items.any(
          (item) =>
              item.label == 'Variable pay' &&
              item.status == PaycheckItemStatus.pending,
        ),
        isTrue,
      );
    });

    test('surfaces claimable reimbursement when receipt evidence exists', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          offerFields: const {
            'components': [
              {
                'label': 'Internet reimbursement',
                'annualAmount': 14400,
                'frequency': 'monthly',
                'classification': 'reimbursement',
              },
            ],
          },
          components: const [],
          evidence: const [
            PaycheckEvidence(
              id: 'bill-1',
              name: 'Broadband bill July',
              detail: 'Uploaded receipt',
              statusLabel: 'CONFIRMED',
              kind: PaycheckEvidenceKind.receipt,
            ),
          ],
          offerLetterAdded: true,
        ),
      );

      expect(output.claimableNow, greaterThan(0));
      expect(
        output.items.any(
          (item) => item.status == PaycheckItemStatus.claimable,
        ),
        isTrue,
      );
    });

    test('adds review item when salary SMS credit differs from payslip net',
        () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          payslipFields: const {'netSalary': 45000},
          components: [
            earning(
              label: 'Basic',
              key: 'basic',
              classification: 'basic_pay',
              amount: 50000,
            ),
            deduction(
              label: 'Income tax',
              key: 'income_tax',
              classification: 'income_tax',
              amount: 5000,
            ),
          ],
          salarySms: const SalarySmsSnapshot(
            latestCreditAmount: 47000,
            latestCreditDate: null,
          ),
          payPeriod: 'July 2026',
        ),
      );

      expect(
        output.items.any((item) => item.id == 'salary-sms-vs-payslip'),
        isTrue,
      );
      expect(output.salarySmsConnected, isTrue);
      expect(
        output.sources.any((source) => source.name == 'Salary SMS'),
        isTrue,
      );
    });

    test('uses salary SMS net when no payslip net is available', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          salarySms: const SalarySmsSnapshot(
            latestCreditAmount: 43210,
            latestCreditDate: null,
          ),
          payPeriod: 'July 2026',
        ),
      );

      expect(output.netCredited, 43210);
      expect(output.grossReceived, 0);
    });

    test('marks PF deductions for review', () {
      final output = ReconciliationEngine.reconcile(
        ReconciliationInput(
          components: [
            earning(
              label: 'Basic',
              key: 'basic',
              classification: 'basic_pay',
              amount: 40000,
            ),
            deduction(
              label: 'Provident fund',
              key: 'employee_pf',
              classification: 'employee_pf',
              amount: 3600,
            ),
          ],
        ),
      );

      expect(
        output.items.any(
          (item) =>
              item.label == 'Provident fund' &&
              item.status == PaycheckItemStatus.review,
        ),
        isTrue,
      );
    });
  });

  test('salarySmsFromSpendMap picks the latest salary credit', () {
    final map = SpendMap(
      txns: [
        FinanceTxn(
          amount: 42000,
          direction: TxnDirection.credit,
          date: DateTime(2026, 6, 28),
          category: 'other',
          isSalary: true,
        ),
        FinanceTxn(
          amount: 45000,
          direction: TxnDirection.credit,
          date: DateTime(2026, 7, 28),
          category: 'other',
          isSalary: true,
        ),
      ],
      windowStart: DateTime(2026, 1, 1),
      windowEnd: DateTime(2026, 7, 28),
      generatedAt: DateTime(2026, 7, 28),
    );

    final snapshot = salarySmsFromSpendMap(map);
    expect(snapshot.latestCreditAmount, 45000);
    expect(snapshot.monthlyAverage, 43500);
    expect(snapshot.isDetected, isTrue);
  });
}
