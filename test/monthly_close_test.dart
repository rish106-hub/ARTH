import 'package:arth/features/monthly_close/engine/monthly_close_engine.dart';
import 'package:arth/features/monthly_close/models/monthly_close_models.dart';
import 'package:arth/models/money_signal_models.dart';
import 'package:arth/models/paycheck.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/spend_map_adjustments_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 28);

  test('monthly close record persists explicit checks and completion date', () {
    var record = const MonthlyCloseRecord(periodKey: '2026-07');
    record = record.mark(MonthlyCloseStep.credit, true, now);
    record = record.mark(MonthlyCloseStep.bills, true, now);
    record = record.mark(MonthlyCloseStep.claims, true, now);

    expect(record.isComplete, isTrue);
    expect(record.completedAt, now);

    final decoded = MonthlyCloseRecord.fromJsonString(record.toJsonString());
    expect(decoded.periodKey, '2026-07');
    expect(decoded.completedSteps, MonthlyCloseStep.values.toSet());
    expect(decoded.completedAt, now);
  });

  test('unchecking a close step reopens the month', () {
    var record = MonthlyCloseRecord(
      periodKey: '2026-07',
      completedSteps: MonthlyCloseStep.values.toSet(),
      completedAt: now,
    );

    record = record.mark(
      MonthlyCloseStep.bills,
      false,
      now.add(const Duration(minutes: 1)),
    );

    expect(record.isComplete, isFalse);
    expect(record.completedAt, isNull);
  });

  test('evidence health and audit trail use real paycheck sources', () {
    final payslipDate = DateTime(2026, 7, 22);
    final snapshot = MonthlyCloseEngine.build(
      paycheck: demoPaycheck,
      income: const IncomeSignal(
        primaryMonthlyIncome: 45920,
        otherMonthlyIncome: 0,
        source: IncomeSignalSource.payslip,
      ),
      adjustments: const SpendMapAdjustments(),
      documents: [
        TaxDocument(
          id: 'payslip',
          fy: '2026-27',
          documentType: 'payslip',
          originalFilename: 'July payslip.pdf',
          mimeType: 'application/pdf',
          byteSize: 100,
          parseStatus: 'parsed',
          parseSummary: const {},
          reviewedAt: payslipDate,
        ),
      ],
      profile: const UserProfile(
        annualCTC: 1000000,
        city: 'Bengaluru',
        paysRent: true,
        monthlyRent: 18000,
      ),
      now: now,
    );

    expect(snapshot.evidenceHealth.readyCount, 3);
    expect(snapshot.evidenceHealth.pendingReceiptCount, 2);
    expect(snapshot.openClaimCount, 3);
    final netAudit =
        snapshot.figureAudits.singleWhere((audit) => audit.id == 'net-pay');
    expect(netAudit.source, 'July payslip.pdf');
    expect(netAudit.confirmedAt, payslipDate);
  });

  test('manual income audit keeps its edit timestamp', () {
    final editedAt = DateTime(2026, 7, 28, 9, 30);
    final snapshot = MonthlyCloseEngine.build(
      paycheck: emptyPaycheck,
      income: const IncomeSignal(
        primaryMonthlyIncome: 60000,
        otherMonthlyIncome: 0,
        source: IncomeSignalSource.edited,
      ),
      adjustments: SpendMapAdjustments(
        manualPrimaryMonthlyIncome: 60000,
        primaryIncomeUpdatedAt: editedAt,
      ),
      documents: const [],
      profile: const UserProfile(),
      now: now,
    );

    final audit = snapshot.figureAudits.single;
    expect(audit.editedByUser, isTrue);
    expect(audit.confirmedAt, editedAt);
  });

  test('cohort percentage stays hidden below the privacy threshold', () {
    final hidden = CohortBenchmark.fromAggregate(
      sampleSize: 29,
      city: 'Bengaluru',
      ctcBandLabel: '₹10L–₹15L',
      averageRentPercent: 18,
    );
    final visible = CohortBenchmark.fromAggregate(
      sampleSize: 30,
      city: 'Bengaluru',
      ctcBandLabel: '₹10L–₹15L',
      averageRentPercent: 18,
    );

    expect(hidden.canShowComparison, isFalse);
    expect(hidden.averageRentPercent, isNull);
    expect(visible.canShowComparison, isTrue);
    expect(visible.averageRentPercent, 18);
  });
}
