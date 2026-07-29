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

  const payslipIncome = IncomeSignal(
    primaryMonthlyIncome: 45920,
    otherMonthlyIncome: 0,
    source: IncomeSignalSource.payslip,
  );

  const profile = UserProfile(
    annualCTC: 1000000,
    city: 'Bengaluru',
    paysRent: true,
    monthlyRent: 18000,
  );

  final salariedPaycheck = emptyPaycheck.copyWith(
    payPeriod: 'July 2026',
    promisedMonthly: 54500,
    grossReceived: 52700,
    netCredited: 45920,
    taxWithheld: 4200,
    otherDeductions: 2580,
    offerLetterAdded: true,
  );

  TaxDocument document({
    required String id,
    required String documentType,
    required String filename,
    required String parseStatus,
    DateTime? reviewedAt,
    DateTime? createdAt,
  }) =>
      TaxDocument(
        id: id,
        fy: '2026-27',
        documentType: documentType,
        originalFilename: filename,
        mimeType: 'application/pdf',
        byteSize: 100,
        parseStatus: parseStatus,
        parseSummary: const {},
        reviewedAt: reviewedAt,
        createdAt: createdAt,
      );

  MonthlyCloseSnapshot build({
    PaycheckState? paycheck,
    IncomeSignal income = payslipIncome,
    SpendMapAdjustments adjustments = const SpendMapAdjustments(),
    List<TaxDocument> documents = const [],
  }) =>
      MonthlyCloseEngine.build(
        paycheck: paycheck ?? salariedPaycheck,
        income: income,
        adjustments: adjustments,
        documents: documents,
        profile: profile,
        now: now,
      );

  EvidenceHealthItem evidenceRow(MonthlyCloseSnapshot snapshot, String label) =>
      snapshot.evidenceHealth.items.singleWhere((item) => item.label == label);

  FigureAudit audit(MonthlyCloseSnapshot snapshot, String id) =>
      snapshot.figureAudits.singleWhere((item) => item.id == id);

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

  test('audit trail dates figures from the confirmed payslip', () {
    final payslipDate = DateTime(2026, 7, 22);
    final snapshot = build(
      documents: [
        document(
          id: 'payslip',
          documentType: 'payslip',
          filename: 'July payslip.pdf',
          parseStatus: 'parsed',
          reviewedAt: payslipDate,
        ),
      ],
    );

    final netPay = audit(snapshot, 'net-pay');
    expect(netPay.source, 'July payslip.pdf');
    expect(netPay.confirmedAt, payslipDate);
    expect(audit(snapshot, 'deductions').confirmedAt, payslipDate);
    expect(audit(snapshot, 'planning-income').confirmedAt, payslipDate);
    expect(evidenceRow(snapshot, 'Payslip').detail, 'Confirmed');
  });

  group('the payslip row waits for a reviewed document', () {
    test('parsed figures without any document are not confirmed', () {
      final snapshot = build();

      expect(
        snapshot.figureAudits.any((item) => item.id == 'gross-pay'),
        isTrue,
      );
      expect(evidenceRow(snapshot, 'Payslip').detail, 'Not confirmed');
      expect(evidenceRow(snapshot, 'Payslip').ready, isFalse);
    });

    test('an unreviewed upload does not confirm the row', () {
      final snapshot = build(
        documents: [
          document(
            id: 'pending',
            documentType: 'payslip',
            filename: 'July payslip.pdf',
            parseStatus: 'needs_confirmation',
            createdAt: DateTime(2026, 7, 24),
          ),
        ],
      );

      expect(evidenceRow(snapshot, 'Payslip').detail, 'Not confirmed');
      expect(evidenceRow(snapshot, 'Payslip').ready, isFalse);
      expect(audit(snapshot, 'gross-pay').confirmedAt, isNull);
    });

    test('a reviewed document confirms the row', () {
      final snapshot = build(
        documents: [
          document(
            id: 'reviewed',
            documentType: 'payslip',
            filename: 'July payslip.pdf',
            parseStatus: 'parsed',
            reviewedAt: DateTime(2026, 7, 24),
          ),
        ],
      );

      expect(evidenceRow(snapshot, 'Payslip').detail, 'Confirmed');
      expect(evidenceRow(snapshot, 'Payslip').ready, isTrue);
    });

    test('a reviewed but undated document still confirms the row', () {
      final snapshot = build(
        documents: [
          document(
            id: 'undated',
            documentType: 'payslip',
            filename: 'Scan.pdf',
            parseStatus: 'parsed',
          ),
        ],
      );

      expect(evidenceRow(snapshot, 'Payslip').detail, 'Confirmed');
      expect(evidenceRow(snapshot, 'Payslip').ready, isTrue);
      expect(audit(snapshot, 'gross-pay').confirmedAt, isNull);
    });
  });

  group('planning income carries its own source date', () {
    test('a payslip source uses the confirmed payslip date', () {
      final payslipDate = DateTime(2026, 7, 22);
      final snapshot = build(
        income: const IncomeSignal(
          primaryMonthlyIncome: 52700,
          otherMonthlyIncome: 0,
          source: IncomeSignalSource.payslipGross,
        ),
        documents: [
          document(
            id: 'payslip',
            documentType: 'payslip',
            filename: 'July payslip.pdf',
            parseStatus: 'parsed',
            reviewedAt: payslipDate,
          ),
        ],
      );

      final income = audit(snapshot, 'planning-income');
      expect(income.confirmedAt, payslipDate);
      expect(income.editedByUser, isFalse);
    });

    test('a salary SMS source uses the last credit it saw', () {
      final seenAt = DateTime(2026, 7, 27);
      final snapshot = build(
        paycheck: salariedPaycheck.copyWith(
          salarySmsCredited: 45100,
          salarySmsLastSeen: seenAt,
          salarySmsConnected: true,
        ),
        income: const IncomeSignal(
          primaryMonthlyIncome: 45100,
          otherMonthlyIncome: 0,
          source: IncomeSignalSource.salarySms,
        ),
      );

      expect(audit(snapshot, 'planning-income').confirmedAt, seenAt);
    });

    test('a payslip source has no date until a payslip is confirmed', () {
      final snapshot = build();

      expect(audit(snapshot, 'planning-income').confirmedAt, isNull);
    });

    test('a CTC estimate is never dated, because nothing confirmed it', () {
      final snapshot = build(
        income: const IncomeSignal(
          primaryMonthlyIncome: 83000,
          otherMonthlyIncome: 0,
          source: IncomeSignalSource.ctcEstimate,
        ),
        documents: [
          document(
            id: 'payslip',
            documentType: 'payslip',
            filename: 'July payslip.pdf',
            parseStatus: 'parsed',
            reviewedAt: DateTime(2026, 7, 22),
          ),
        ],
      );

      expect(audit(snapshot, 'planning-income').confirmedAt, isNull);
    });

    test('a disconnected salary SMS leaves the figure undated', () {
      final snapshot = build(
        paycheck: salariedPaycheck.copyWith(
          salarySmsCredited: 45100,
          salarySmsLastSeen: DateTime(2026, 7, 27),
          salarySmsConnected: false,
        ),
        income: const IncomeSignal(
          primaryMonthlyIncome: 45100,
          otherMonthlyIncome: 0,
          source: IncomeSignalSource.salarySms,
        ),
      );

      expect(audit(snapshot, 'planning-income').confirmedAt, isNull);
    });
  });

  test('a confirmed older payslip outranks a newer unconfirmed upload', () {
    final confirmedDate = DateTime(2026, 7, 10);
    final snapshot = build(
      documents: [
        document(
          id: 'newer-unconfirmed',
          documentType: 'payslip',
          filename: 'August payslip.pdf',
          parseStatus: 'needs_confirmation',
          createdAt: DateTime(2026, 8, 2),
        ),
        document(
          id: 'older-confirmed',
          documentType: 'payslip',
          filename: 'July payslip.pdf',
          parseStatus: 'parsed',
          reviewedAt: confirmedDate,
        ),
      ],
    );

    final netPay = audit(snapshot, 'net-pay');
    expect(netPay.source, 'July payslip.pdf');
    expect(netPay.confirmedAt, confirmedDate);
  });

  test('an added offer is not reported as confirmed until it is reviewed', () {
    final addedOnly = build();
    expect(evidenceRow(addedOnly, 'Offer').detail, 'Added, not confirmed');
    expect(evidenceRow(addedOnly, 'Offer').ready, isFalse);
    expect(audit(addedOnly, 'promised-pay').confirmedAt, isNull);
    expect(
      audit(addedOnly, 'promised-pay').detail,
      'Monthly value from the offer you added. Not confirmed yet.',
    );

    final offerDate = DateTime(2026, 4, 1);
    final confirmed = build(
      documents: [
        document(
          id: 'offer',
          documentType: 'offerLetter',
          filename: 'Offer.pdf',
          parseStatus: 'parsed',
          reviewedAt: offerDate,
        ),
      ],
    );
    expect(evidenceRow(confirmed, 'Offer').detail, 'Confirmed');
    expect(evidenceRow(confirmed, 'Offer').ready, isTrue);
    expect(audit(confirmed, 'promised-pay').confirmedAt, offerDate);
  });

  test('a missing offer reads as not added rather than unconfirmed', () {
    final snapshot = build(
      paycheck: salariedPaycheck.copyWith(offerLetterAdded: false),
    );

    expect(evidenceRow(snapshot, 'Offer').detail, 'Not added');
    expect(evidenceRow(snapshot, 'Offer').ready, isFalse);
    expect(
      audit(snapshot, 'promised-pay').detail,
      'Promised pay is available, but no offer letter is on file.',
    );
  });

  test('pay difference needs both offer and payslip confirmation', () {
    final payslipDate = DateTime(2026, 7, 22);
    final payslipOnly = build(
      documents: [
        document(
          id: 'payslip',
          documentType: 'payslip',
          filename: 'July payslip.pdf',
          parseStatus: 'parsed',
          reviewedAt: payslipDate,
        ),
      ],
    );

    expect(audit(payslipOnly, 'pay-difference').confirmedAt, isNull);
    expect(
      audit(payslipOnly, 'pay-difference').detail,
      contains('Both sources are not confirmed yet'),
    );

    final bothConfirmed = build(
      documents: [
        document(
          id: 'payslip',
          documentType: 'payslip',
          filename: 'July payslip.pdf',
          parseStatus: 'parsed',
          reviewedAt: payslipDate,
        ),
        document(
          id: 'offer',
          documentType: 'offerLetter',
          filename: 'Offer.pdf',
          parseStatus: 'parsed',
          reviewedAt: DateTime(2026, 4, 1),
        ),
      ],
    );

    expect(audit(bothConfirmed, 'pay-difference').confirmedAt, payslipDate);
    expect(
      audit(bothConfirmed, 'pay-difference').detail,
      'Confirmed promised monthly pay minus confirmed gross earnings.',
    );
  });

  test('an undated confirmed payslip never reports an epoch date', () {
    final snapshot = build(
      documents: [
        document(
          id: 'undated',
          documentType: 'payslip',
          filename: 'Scan.pdf',
          parseStatus: 'parsed',
        ),
      ],
    );

    final netPay = audit(snapshot, 'net-pay');
    expect(netPay.source, 'Scan.pdf');
    expect(netPay.confirmedAt, isNull);
    for (final item in snapshot.figureAudits) {
      expect(item.confirmedAt?.year, anyOf(isNull, greaterThan(1970)));
    }
  });

  test('salary SMS dates net pay when there is no payslip', () {
    final seenAt = DateTime(2026, 7, 27);
    final snapshot = build(
      paycheck: emptyPaycheck.copyWith(
        payPeriod: 'July 2026',
        netCredited: 45920,
        salarySmsCredited: 45920,
        salarySmsLastSeen: seenAt,
        salarySmsConnected: true,
      ),
      income: const IncomeSignal(
        primaryMonthlyIncome: 45920,
        otherMonthlyIncome: 0,
        source: IncomeSignalSource.salarySms,
      ),
    );

    final netPay = audit(snapshot, 'net-pay');
    expect(netPay.source, 'Salary SMS');
    expect(netPay.confirmedAt, seenAt);
  });

  test('a manual income edit keeps its own edit timestamp', () {
    final editedAt = DateTime(2026, 7, 28, 9, 30);
    final snapshot = build(
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
    );

    final income = snapshot.figureAudits.single;
    expect(income.editedByUser, isTrue);
    expect(income.confirmedAt, editedAt);
  });

  test('planning income names every contributing source', () {
    final snapshot = build(
      income: const IncomeSignal(
        primaryMonthlyIncome: 45920,
        otherMonthlyIncome: 8000,
        source: IncomeSignalSource.payslip,
      ),
    );

    expect(audit(snapshot, 'planning-income').source, contains('other income'));
    expect(audit(snapshot, 'planning-income').amount, 53920);
  });

  group('salary credit confirmation', () {
    test('a payslip alone cannot confirm a bank credit', () {
      final snapshot = build();

      expect(snapshot.creditStatus, MonthlyCloseCreditStatus.smsNotConnected);
      expect(snapshot.creditConfirmed, isFalse);
      expect(snapshot.creditAmount, 0);
    });

    test('a connected SMS with no credit yet stays unconfirmed', () {
      final snapshot = build(
        paycheck: salariedPaycheck.copyWith(salarySmsConnected: true),
      );

      expect(snapshot.creditStatus, MonthlyCloseCreditStatus.awaitingCredit);
      expect(snapshot.creditConfirmed, isFalse);
      expect(snapshot.creditAmount, 0);
    });

    test('a real salary SMS credit confirms and reports its own amount', () {
      final snapshot = build(
        paycheck: salariedPaycheck.copyWith(
          salarySmsCredited: 45100,
          salarySmsLastSeen: DateTime(2026, 7, 27),
          salarySmsConnected: true,
        ),
      );

      expect(snapshot.creditStatus, MonthlyCloseCreditStatus.confirmed);
      expect(snapshot.creditConfirmed, isTrue);
      expect(snapshot.creditAmount, 45100);
      expect(snapshot.creditAmount, isNot(salariedPaycheck.netCredited));
    });

    test('demo figures confirm nothing at all', () {
      final snapshot = build(paycheck: demoPaycheck);

      expect(snapshot.creditStatus, MonthlyCloseCreditStatus.demoData);
      expect(snapshot.creditConfirmed, isFalse);
      expect(snapshot.creditAmount, 0);
      expect(snapshot.evidenceHealth.readyCount, 0);
      expect(evidenceRow(snapshot, 'Offer').detail, 'Demo data');
      expect(evidenceRow(snapshot, 'Payslip').detail, 'Demo data');
      expect(evidenceRow(snapshot, 'Salary SMS').detail, 'Demo data');
      for (final item in snapshot.figureAudits) {
        expect(item.source, 'Demo data');
        expect(item.detail, 'Sample figure for exploring ARTH. Not confirmed.');
        expect(item.confirmedAt, isNull);
      }
    });

    test('demo figures stay unconfirmed even with real documents on file', () {
      final snapshot = build(
        paycheck: demoPaycheck,
        documents: [
          document(
            id: 'payslip',
            documentType: 'payslip',
            filename: 'July payslip.pdf',
            parseStatus: 'parsed',
            reviewedAt: DateTime(2026, 7, 22),
          ),
        ],
      );

      expect(snapshot.creditStatus, MonthlyCloseCreditStatus.demoData);
      expect(audit(snapshot, 'net-pay').confirmedAt, isNull);
      expect(evidenceRow(snapshot, 'Payslip').ready, isFalse);
    });
  });

  group('cohort privacy floor', () {
    CohortBenchmark cohortOf(int sampleSize) => CohortBenchmark.fromAggregate(
          sampleSize: sampleSize,
          city: 'Bengaluru',
          ctcBandLabel: '₹10L–₹15L',
          averageRentPercent: 18,
        );

    test('an empty cohort shows nothing', () {
      final cohort = cohortOf(0);
      expect(cohort.canShowComparison, isFalse);
      expect(cohort.averageRentPercent, isNull);
    });

    test('one short of the floor still shows nothing', () {
      final cohort = cohortOf(29);
      expect(cohort.canShowComparison, isFalse);
      expect(cohort.averageRentPercent, isNull);
    });

    test('the floor itself is the first visible sample size', () {
      final cohort = cohortOf(30);
      expect(cohort.canShowComparison, isTrue);
      expect(cohort.averageRentPercent, 18);
    });

    test('the floor is fixed at 30 and cannot be lowered by a caller', () {
      expect(CohortBenchmark.minimumPrivateSample, 30);
      const forged = CohortBenchmark(
        status: CohortBenchmarkStatus.available,
        sampleSize: 5,
        averageRentPercent: 18,
      );

      expect(forged.minimumSampleSize, 30);
      expect(forged.canShowComparison, isFalse);
    });
  });
}
