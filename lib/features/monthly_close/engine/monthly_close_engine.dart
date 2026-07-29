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
    // Sample figures may be on screen, but they are never evidence.
    final isDemo = paycheck.usingSampleData;
    final activeDocuments =
        documents.where((document) => document.active).toList();
    // Only a reviewed document can date or confirm a figure, so a newer
    // unconfirmed upload never outranks an older confirmed one.
    final latestPayslip = isDemo
        ? null
        : _latestConfirmed(
            activeDocuments.where((document) => document.isPayslip),
          );
    final latestOffer = isDemo
        ? null
        : _latestConfirmed(
            activeDocuments.where(
              (document) => document.documentType == 'offerLetter',
            ),
          );
    final pendingReceipts = paycheck.evidence
        .where(
          (item) =>
              item.kind == PaycheckEvidenceKind.receipt && item.needsAction,
        )
        .length;

    // Parsed figures alone are not confirmation. The row only reads Confirmed
    // once a reviewed payslip document backs those figures.
    final payslipConfirmed =
        !isDemo && paycheck.grossReceived > 0 && latestPayslip != null;
    final salarySmsConnected = !isDemo && paycheck.salarySmsConnected;

    final evidence = EvidenceHealth(
      pendingReceiptCount: pendingReceipts,
      items: [
        EvidenceHealthItem(
          label: 'Offer',
          detail: switch ((isDemo, paycheck.offerLetterAdded, latestOffer)) {
            (true, _, _) => 'Demo data',
            (_, false, _) => 'Not added',
            (_, true, null) => 'Added, not confirmed',
            (_, true, _) => 'Confirmed',
          },
          ready: !isDemo && paycheck.offerLetterAdded && latestOffer != null,
        ),
        EvidenceHealthItem(
          label: 'Payslip',
          detail: isDemo
              ? 'Demo data'
              : payslipConfirmed
                  ? 'Confirmed'
                  : 'Not confirmed',
          ready: payslipConfirmed,
        ),
        EvidenceHealthItem(
          label: 'Salary SMS',
          detail: isDemo
              ? 'Demo data'
              : salarySmsConnected
                  ? 'Connected'
                  : 'Not connected',
          ready: salarySmsConnected,
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

    final payslipLabel =
        latestPayslip?.displayName ?? '${paycheck.payPeriod} payslip';
    final payslipDate = _documentDate(latestPayslip);
    final offerDate = _documentDate(latestOffer);

    final audits = <FigureAudit>[
      if (income.monthlyIncome > 0)
        FigureAudit(
          id: 'planning-income',
          label: 'Monthly planning income',
          amount: income.monthlyIncome,
          source: income.sourceLabel,
          detail: income.isEdited
              ? 'Your local edit is used across paycheck, spend, goal, and tax.'
              : _incomeDetail(income, paycheck),
          confirmedAt: _incomeConfirmedAt(
            income: income,
            adjustments: adjustments,
            payslipDate: payslipDate,
            salarySmsLastSeen:
                salarySmsConnected ? paycheck.salarySmsLastSeen : null,
          ),
          editedByUser: income.isEdited,
        ),
      if (paycheck.promisedMonthly > 0)
        FigureAudit(
          id: 'promised-pay',
          label: 'Promised monthly pay',
          amount: paycheck.promisedMonthly,
          source: latestOffer?.displayName ?? 'Offer letter',
          detail: latestOffer != null
              ? 'Monthly value from the confirmed offer.'
              : paycheck.offerLetterAdded
                  ? 'Monthly value from the offer you added. Not confirmed yet.'
                  : 'Promised pay is available, but no offer letter is on file.',
          confirmedAt: offerDate,
        ),
      if (paycheck.grossReceived > 0)
        FigureAudit(
          id: 'gross-pay',
          label: 'Gross earnings',
          amount: paycheck.grossReceived,
          source: payslipLabel,
          detail: latestPayslip == null
              ? 'Sum of payslip earnings. No confirmed payslip on file yet.'
              : 'Sum of confirmed payslip earnings.',
          confirmedAt: payslipDate,
        ),
      if (paycheck.promisedMonthly > 0 && paycheck.grossReceived > 0)
        FigureAudit(
          id: 'pay-difference',
          label: 'Pay difference',
          amount: (paycheck.promisedMonthly - paycheck.grossReceived).abs(),
          source: 'Offer and payslip comparison',
          detail: latestOffer != null && latestPayslip != null
              ? 'Confirmed promised monthly pay minus confirmed gross earnings.'
              : 'Promised monthly pay minus gross earnings. Both sources are not confirmed yet.',
          confirmedAt:
              latestOffer != null && latestPayslip != null ? payslipDate : null,
        ),
      if (paycheck.netCredited > 0)
        FigureAudit(
          id: 'net-pay',
          label: 'Net pay',
          amount: paycheck.netCredited,
          source: paycheck.grossReceived > 0 ? payslipLabel : 'Salary SMS',
          detail: paycheck.grossReceived > 0
              ? 'Gross earnings minus payslip deductions.'
              : 'Latest trusted salary credit.',
          confirmedAt: paycheck.grossReceived > 0
              ? payslipDate
              : (salarySmsConnected ? paycheck.salarySmsLastSeen : null),
        ),
      if (paycheck.taxWithheld + paycheck.otherDeductions > 0)
        FigureAudit(
          id: 'deductions',
          label: 'Deductions',
          amount: paycheck.taxWithheld + paycheck.otherDeductions,
          source: payslipLabel,
          detail: 'Tax and other payslip deductions.',
          confirmedAt: payslipDate,
        ),
    ];
    final safeAudits = isDemo
        ? audits
            .map(
              (audit) => FigureAudit(
                id: audit.id,
                label: audit.label,
                amount: audit.amount,
                source: 'Demo data',
                detail: 'Sample figure for exploring ARTH. Not confirmed.',
              ),
            )
            .toList(growable: false)
        : audits;

    return MonthlyCloseSnapshot(
      periodLabel: DateFormat('MMMM yyyy').format(now),
      // A payslip states what the employer says it paid. Only a salary SMS
      // shows money reaching the account, so only it can back this figure.
      creditAmount: isDemo ? 0 : paycheck.salarySmsCredited,
      creditStatus: switch ((isDemo, salarySmsConnected)) {
        (true, _) => MonthlyCloseCreditStatus.demoData,
        (_, false) => MonthlyCloseCreditStatus.smsNotConnected,
        _ when paycheck.salarySmsCredited > 0 =>
          MonthlyCloseCreditStatus.confirmed,
        _ => MonthlyCloseCreditStatus.awaitingCredit,
      },
      openClaimCount: paycheck.items
          .where(
            (item) =>
                item.status == PaycheckItemStatus.claimable ||
                item.status == PaycheckItemStatus.review,
          )
          .length,
      evidenceHealth: evidence,
      figureAudits: safeAudits,
      cohort: cohort ?? _unavailableCohort(profile),
    );
  }

  /// Newest reviewed document, preferring ones that carry a real date. Returns
  /// null when nothing is reviewed, so no figure claims evidence it lacks.
  static TaxDocument? _latestConfirmed(Iterable<TaxDocument> documents) {
    final confirmed = documents.where((document) => document.reviewed).toList()
      ..sort(_byNewestKnownDate);
    return confirmed.firstOrNull;
  }

  static int _byNewestKnownDate(TaxDocument a, TaxDocument b) {
    final aDate = _documentDate(a);
    final bDate = _documentDate(b);
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  /// Real document date only. There is no epoch fallback, so the UI can never
  /// render a 1970 timestamp.
  static DateTime? _documentDate(TaxDocument? document) =>
      document?.reviewedAt ?? document?.createdAt;

  /// Dates the planning figure from whichever source produced it. CTC estimates
  /// and a missing source carry no date, because nothing confirmed them.
  static DateTime? _incomeConfirmedAt({
    required IncomeSignal income,
    required SpendMapAdjustments adjustments,
    required DateTime? payslipDate,
    required DateTime? salarySmsLastSeen,
  }) =>
      switch (income.source) {
        IncomeSignalSource.payslip ||
        IncomeSignalSource.payslipGross =>
          payslipDate,
        IncomeSignalSource.salarySms => salarySmsLastSeen,
        IncomeSignalSource.edited => adjustments.primaryIncomeUpdatedAt,
        IncomeSignalSource.ctcEstimate || IncomeSignalSource.missing => null,
      };

  static String _incomeDetail(IncomeSignal income, PaycheckState paycheck) =>
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
      );
    }
    final lower = (profile.annualCTC ~/ 500000) * 5;
    final upper = lower + 5;
    return CohortBenchmark(
      status: CohortBenchmarkStatus.waitingForSample,
      sampleSize: 0,
      city: city,
      ctcBandLabel: '₹${lower}L–₹${upper}L',
    );
  }
}
