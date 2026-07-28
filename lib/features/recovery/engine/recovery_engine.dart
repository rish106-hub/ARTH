import '../../../models/paycheck.dart';
import '../models/recovery_models.dart';

class EmployerDataset {
  const EmployerDataset({
    required this.version,
    required this.playbooks,
    required this.genericRules,
  });

  final String version;
  final List<EmployerPlaybook> playbooks;
  final List<EmployerRule> genericRules;

  factory EmployerDataset.fromJson(Map<String, dynamic> json) =>
      EmployerDataset(
        version: json['version']?.toString() ?? 'unknown',
        playbooks: (json['employers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EmployerPlaybook.fromJson)
            .toList(growable: false),
        genericRules: (json['genericRules'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EmployerRule.fromJson)
            .toList(growable: false),
      );
}

class RecoveryEngine {
  const RecoveryEngine._();

  static RecoveryState derive({
    required RecoveryState saved,
    required PaycheckState paycheck,
    required EmployerDataset dataset,
    required DateTime now,
  }) {
    final playbook = playbookFor(paycheck.employer, dataset);
    if (paycheck.usingSampleData) {
      return saved.copyWith(
        datasetVersion: dataset.version,
        playbook: playbook,
      );
    }
    final cases = _mergeCases(saved.claimCases, paycheck, now);
    final benefits = _deriveBenefits(
      saved.benefits,
      paycheck,
      cases,
      [...dataset.genericRules, ...playbook.rules],
      now,
    );
    final history = _mergeHistory(saved.history, paycheck, now);
    final checklists = _mergeChecklists(
      saved.checklists,
      paycheck,
      cases,
      now,
    );
    return RecoveryState(
      schemaVersion: saved.schemaVersion,
      datasetVersion: dataset.version,
      claimCases: cases,
      history: history,
      benefits: benefits,
      checklists: checklists,
      playbook: playbook,
    );
  }

  static EmployerPlaybook playbookFor(
    String employer,
    EmployerDataset dataset,
  ) {
    final normalized = employer.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      for (final playbook in dataset.playbooks) {
        final candidates = [playbook.name, ...playbook.aliases];
        if (candidates.any(
          (candidate) => normalized.contains(candidate.toLowerCase()),
        )) {
          return playbook;
        }
      }
    }
    return const EmployerPlaybook(
      key: 'generic',
      name: 'Your employer',
      aliases: [],
      status: 'generic',
      sourceUrl: '',
      rules: [],
    );
  }

  static List<ClaimCase> _mergeCases(
    List<ClaimCase> saved,
    PaycheckState paycheck,
    DateTime now,
  ) {
    final byItem = {for (final item in saved) item.paycheckItemId: item};
    for (final item in paycheck.items.where(
      (value) =>
          value.status == PaycheckItemStatus.claimable ||
          value.status == PaycheckItemStatus.review,
    )) {
      final existing = byItem[item.id];
      byItem[item.id] = existing == null
          ? ClaimCase(
              id: 'claim-${item.id}',
              paycheckItemId: item.id,
              label: item.label,
              detail: item.detail,
              amount: item.amount,
              status: paycheck.preparedClaims.contains(item.id)
                  ? ClaimCaseStatus.prepared
                  : ClaimCaseStatus.review,
              createdAt: now,
            )
          : existing.copyWith(
              label: item.label,
              detail: item.detail,
              amount: item.amount,
              status: paycheck.preparedClaims.contains(item.id) &&
                      existing.status == ClaimCaseStatus.review
                  ? ClaimCaseStatus.prepared
                  : existing.status,
            );
    }
    final values = byItem.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  static List<ReconciliationSnapshot> _mergeHistory(
    List<ReconciliationSnapshot> saved,
    PaycheckState paycheck,
    DateTime now,
  ) {
    final confirmedPayslip = paycheck.evidence.any(
      (value) =>
          value.kind == PaycheckEvidenceKind.payslip &&
          value.statusLabel == 'CONFIRMED',
    );
    if (!confirmedPayslip || paycheck.grossReceived <= 0) return saved;
    final id = [
      _slug(paycheck.payPeriod),
      paycheck.promisedMonthly,
      paycheck.grossReceived,
      paycheck.netCredited,
      paycheck.salarySmsCredited,
    ].join('-');
    if (saved.any((value) => value.id == id)) return saved;
    final snapshot = ReconciliationSnapshot(
      id: id,
      payPeriod: paycheck.payPeriod,
      createdAt: now,
      promised: paycheck.promisedMonthly,
      grossPaid: paycheck.grossReceived,
      netPaid: paycheck.netCredited,
      salaryCredit: paycheck.salarySmsCredited,
      delta: paycheck.grossReceived - paycheck.promisedMonthly,
      itemAmounts: {
        for (final item in paycheck.items) item.id: item.amount,
      },
      itemLabels: {
        for (final item in paycheck.items) item.id: item.label,
      },
      evidenceIds: paycheck.evidence
          .where((value) => value.statusLabel == 'CONFIRMED')
          .map((value) => value.id)
          .toList(growable: false),
    );
    return [snapshot, ...saved].take(24).toList(growable: false);
  }

  static List<BenefitLedgerEntry> _deriveBenefits(
    List<BenefitLedgerEntry> saved,
    PaycheckState paycheck,
    List<ClaimCase> cases,
    List<EmployerRule> rules,
    DateTime now,
  ) {
    final oldById = {for (final value in saved) value.id: value};
    final benefits = <BenefitLedgerEntry>[];
    for (final item in paycheck.items.where(
      (value) =>
          value.status == PaycheckItemStatus.claimable ||
          value.status == PaycheckItemStatus.pending,
    )) {
      final lower = '${item.label} ${item.detail}'.toLowerCase();
      EmployerRule? match;
      for (final rule in rules) {
        if (rule.matchTerms.any(
          (term) => lower.contains(term.toLowerCase()),
        )) {
          match = rule;
          break;
        }
      }
      final old = oldById[item.id];
      final userConfirmed = old?.source.startsWith('Added by you') == true;
      final claimed = cases
          .where(
            (value) =>
                value.paycheckItemId == item.id &&
                value.status == ClaimCaseStatus.paid,
          )
          .fold<int>(0, (sum, value) => sum + value.amount);
      DateTime? deadline;
      if (match?.deadlineMonth != null && match?.deadlineDay != null) {
        final candidate = DateTime(
          now.year,
          match!.deadlineMonth!,
          match.deadlineDay!,
        );
        deadline = candidate.isBefore(now)
            ? DateTime(now.year + 1, candidate.month, candidate.day)
            : candidate;
      }
      benefits.add(
        BenefitLedgerEntry(
          id: item.id,
          label: item.label,
          annualCap: userConfirmed
              ? old!.annualCap
              : match?.annualCap ?? old?.annualCap,
          claimed: claimed,
          resetMonth: userConfirmed
              ? old!.resetMonth
              : match?.resetMonth ?? old?.resetMonth,
          deadline: userConfirmed ? old!.deadline : deadline ?? old?.deadline,
          source: userConfirmed
              ? old!.source
              : match?.sourceLabel ??
                  old?.source ??
                  'No verified employer rule. Check your policy.',
        ),
      );
    }
    return benefits;
  }

  static List<PaydayChecklist> _mergeChecklists(
    List<PaydayChecklist> saved,
    PaycheckState paycheck,
    List<ClaimCase> cases,
    DateTime now,
  ) {
    if (!paycheck.salarySmsConnected || paycheck.salarySmsLastSeen == null) {
      return saved;
    }
    final seen = paycheck.salarySmsLastSeen!;
    final key = '${seen.year}-${seen.month.toString().padLeft(2, '0')}';
    final existing = saved.where((value) => value.monthKey == key).firstOrNull;
    final hasConfirmedPayslip = paycheck.evidence.any(
      (value) =>
          value.kind == PaycheckEvidenceKind.payslip &&
          value.statusLabel == 'CONFIRMED',
    );
    final activeCases = cases.where(
      (value) =>
          value.status == ClaimCaseStatus.review ||
          value.status == ClaimCaseStatus.prepared,
    );
    final derived = PaydayChecklist(
      monthKey: key,
      creditFound: true,
      payslipChecked: existing?.payslipChecked == true || hasConfirmedPayslip,
      claimItemsReviewed: existing?.claimItemsReviewed == true ||
          activeCases.every((value) => value.status != ClaimCaseStatus.review),
      completedAt: existing?.completedAt,
    );
    final finalized = derived.complete && derived.completedAt == null
        ? derived.copyWith(completedAt: now)
        : derived;
    return [
      finalized,
      ...saved.where((value) => value.monthKey != key),
    ].take(18).toList(growable: false);
  }

  static String _slug(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
