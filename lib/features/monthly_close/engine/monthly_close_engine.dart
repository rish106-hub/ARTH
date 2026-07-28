import 'package:intl/intl.dart';

import '../../../models/money_signal_models.dart';
import '../../../models/paycheck.dart';
import '../../../models/tax_document.dart';
import '../../../models/user_profile.dart';
import '../../../providers/spend_map_adjustments_provider.dart';
import '../models/monthly_close_models.dart';

class MonthlyCloseEngine {
  const MonthlyCloseEngine._();

  static String periodKey(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}';

  static MonthlyCloseSnapshot build({
    required PaycheckState paycheck,
    required IncomeSignal income,
    required SpendMapAdjustments adjustments,
    required List<TaxDocument> documents,
    required UserProfile profile,
    required DateTime now,
    CohortBenchmark? cohort,
  }) {
    final activeDocuments =
        documents.where((document) => document.active).toList();
    final payslips = activeDocuments
        .where((document) => document.isPayslip)
        .toList()
      ..sort((a, b) => _documentDate(b).compareTo(_documentDate(a)));
    final offerLetters = activeDocuments
        .where((document) => document.documentType == 'offerLetter')
        .toList()
      ..sort((a, b) => _documentDate(b).compareTo(_documentDate(a)));
    final latestPayslip = payslips.firstOrNull;
    final latestOffer = offerLetters.firstOrNull;
    final pendingReceipts = paycheck.evidence
        .where((item) =>
            item.kind == PaycheckEvidenceKind.receipt && item.needsAction)
        .length;

    final evidence = EvidenceHealth(
      pendingReceiptCount: pendingReceipts,
      items: [
        EvidenceHealthItem(
          label: 'Offer',
          detail: paycheck.offerLetterAdded ? 'Confirmed' : 'Not added',
          ready: paycheck.offerLetterAdded,
        ),
        EvidenceHealthItem(
          label: 'Payslip',
          detail: paycheck.grossReceived > 0 ? 'Confirmed' : 'Not confirmed',
          ready: paycheck.grossReceived > 0,
        ),
        EvidenceHealthItem(
          label: 'Salary SMS',
          detail: paycheck.salarySmsConnected ? 'Connected' : 'Not connected',
          ready: paycheck.salarySmsConnected,
        ),
        EvidenceHealthItem(
          label: 'Receipts',
          detail: pendingReceipts == 0
              ? 'No review pending'
              : '$pendingReceipts pending review',
          ready: pendingReceipts == 0,
        ),
      ],
    );

    final audits = <FigureAudit>[
      if (income.monthlyIncome > 0)
        FigureAudit(
          id: 'planning-income',
          label: 'Monthly planning income',
          amount: income.monthlyIncome,
          source: income.source.label,
          detail: income.isEdited
              ? 'Your local edit is used across paycheck, spend, goal, and tax.'
              : _incomeDetail(income, paycheck),
          confirmedAt:
              income.isEdited ? adjustments.primaryIncomeUpdatedAt : null,
          editedByUser: income.isEdited,
        ),
      if (paycheck.promisedMonthly > 0)
        FigureAudit(
          id: 'promised-pay',
          label: 'Promised monthly pay',
          amount: paycheck.promisedMonthly,
          source: latestOffer?.displayName ?? 'Offer letter',
          detail: 'Monthly value from the confirmed offer.',
          confirmedAt: latestOffer == null ? null : _documentDate(latestOffer),
        ),
      if (paycheck.grossReceived > 0)
        FigureAudit(
          id: 'gross-pay',
          label: 'Gross earnings',
          amount: paycheck.grossReceived,
          source: latestPayslip?.displayName ?? '${paycheck.payPeriod} payslip',
          detail: 'Sum of confirmed payslip earnings.',
          confirmedAt:
              latestPayslip == null ? null : _documentDate(latestPayslip),
        ),
      if (paycheck.promisedMonthly > 0 && paycheck.grossReceived > 0)
        FigureAudit(
          id: 'pay-difference',
          label: 'Pay difference',
          amount: (paycheck.promisedMonthly - paycheck.grossReceived).abs(),
          source: 'Offer and payslip comparison',
          detail:
              'Confirmed promised monthly pay minus confirmed gross earnings.',
          confirmedAt:
              latestPayslip == null ? null : _documentDate(latestPayslip),
        ),
      if (paycheck.netCredited > 0)
        FigureAudit(
          id: 'net-pay',
          label: 'Net pay',
          amount: paycheck.netCredited,
          source: paycheck.grossReceived > 0
              ? latestPayslip?.displayName ?? '${paycheck.payPeriod} payslip'
              : 'Salary SMS',
          detail: paycheck.grossReceived > 0
              ? 'Gross earnings minus confirmed deductions.'
              : 'Latest trusted salary credit.',
          confirmedAt: paycheck.grossReceived > 0
              ? (latestPayslip == null ? null : _documentDate(latestPayslip))
              : paycheck.salarySmsLastSeen,
        ),
      if (paycheck.taxWithheld + paycheck.otherDeductions > 0)
        FigureAudit(
          id: 'deductions',
          label: 'Deductions',
          amount: paycheck.taxWithheld + paycheck.otherDeductions,
          source: latestPayslip?.displayName ?? '${paycheck.payPeriod} payslip',
          detail: 'Tax and other confirmed payslip deductions.',
          confirmedAt:
              latestPayslip == null ? null : _documentDate(latestPayslip),
        ),
    ];

    return MonthlyCloseSnapshot(
      periodLabel: DateFormat('MMMM yyyy').format(now),
      creditAmount: paycheck.netCredited > 0
          ? paycheck.netCredited
          : paycheck.salarySmsCredited,
      openClaimCount: paycheck.items
          .where((item) =>
              item.status == PaycheckItemStatus.claimable ||
              item.status == PaycheckItemStatus.review)
          .length,
      evidenceHealth: evidence,
      figureAudits: audits,
      cohort: cohort ?? _unavailableCohort(profile),
    );
  }

  static DateTime _documentDate(TaxDocument document) =>
      document.reviewedAt ??
      document.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static String _incomeDetail(
    IncomeSignal income,
    PaycheckState paycheck,
  ) =>
      switch (income.source) {
        IncomeSignalSource.payslip =>
          'Net pay from the confirmed ${paycheck.payPeriod} payslip.',
        IncomeSignalSource.payslipGross =>
          'Gross pay from the confirmed ${paycheck.payPeriod} payslip.',
        IncomeSignalSource.salarySms => 'Average of trusted salary credits.',
        IncomeSignalSource.ctcEstimate =>
          'Monthly estimate from confirmed annual CTC.',
        IncomeSignalSource.edited => 'Your local edit.',
        IncomeSignalSource.missing => 'No source is connected.',
      };

  static CohortBenchmark _unavailableCohort(UserProfile profile) {
    final city = profile.city.trim();
    if (city.isEmpty || profile.annualCTC <= 0 || profile.monthlyRent <= 0) {
      return const CohortBenchmark(
        status: CohortBenchmarkStatus.profileNeeded,
        sampleSize: 0,
        minimumSampleSize: CohortBenchmark.minimumPrivateSample,
      );
    }
    final lower = (profile.annualCTC ~/ 500000) * 5;
    final upper = lower + 5;
    return CohortBenchmark(
      status: CohortBenchmarkStatus.waitingForSample,
      sampleSize: 0,
      minimumSampleSize: CohortBenchmark.minimumPrivateSample,
      city: city,
      ctcBandLabel: '₹${lower}L–₹${upper}L',
    );
  }
}
