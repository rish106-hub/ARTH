import 'package:arth/features/recovery/engine/recovery_engine.dart';
import 'package:arth/features/recovery/models/recovery_models.dart';
import 'package:arth/models/paycheck.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 28);
  const dataset = EmployerDataset(
    version: 'test-v1',
    playbooks: [
      EmployerPlaybook(
        key: 'northstar',
        name: 'Northstar Labs',
        aliases: ['Northstar'],
        status: 'verified',
        sourceUrl: 'https://example.com/policy',
        rules: [
          EmployerRule(
            id: 'internet',
            matchTerms: ['internet'],
            sourceLabel: 'Verified test policy',
            annualCap: 12000,
            resetMonth: 4,
          ),
        ],
      ),
    ],
    genericRules: [],
  );

  PaycheckState paycheck() => PaycheckState(
        employeeName: 'Aarav',
        employer: 'Northstar Labs India',
        role: 'Analyst',
        payPeriod: 'July 2026',
        promisedMonthly: 50000,
        grossReceived: 48000,
        netCredited: 45000,
        claimableNow: 1000,
        taxWithheld: 2000,
        otherDeductions: 1000,
        annualBenefits: 12000,
        usingSampleData: false,
        offerLetterAdded: true,
        inboxConnected: false,
        preparedClaims: const {},
        items: const [
          PaycheckItem(
            id: 'internet',
            label: 'Internet reimbursement',
            detail: 'Bill found',
            amount: 1000,
            status: PaycheckItemStatus.claimable,
          ),
        ],
        components: const [],
        sources: const [],
        evidence: const [
          PaycheckEvidence(
            id: 'payslip-july',
            name: 'July payslip',
            detail: 'Confirmed',
            statusLabel: 'CONFIRMED',
            kind: PaycheckEvidenceKind.payslip,
          ),
        ],
        salarySmsCredited: 45000,
        salarySmsLastSeen: DateTime(2026, 7, 1),
        salarySmsConnected: true,
      );

  test('derives claim, snapshot, benefit, checklist, and playbook', () {
    final state = RecoveryEngine.derive(
      saved: const RecoveryState(),
      paycheck: paycheck(),
      dataset: dataset,
      now: now,
    );

    expect(state.datasetVersion, 'test-v1');
    expect(state.playbook?.key, 'northstar');
    expect(state.claimCases.single.paycheckItemId, 'internet');
    expect(state.history.single.delta, -2000);
    expect(
      state.history.single.itemLabels['internet'],
      'Internet reimbursement',
    );
    expect(state.benefits.single.annualCap, 12000);
    expect(state.benefits.single.remaining, 12000);
    expect(state.checklists.single.monthKey, '2026-07');
    expect(state.checklists.single.creditFound, isTrue);
    expect(state.checklists.single.payslipChecked, isTrue);
    expect(state.checklists.single.claimItemsReviewed, isFalse);
  });

  test('does not duplicate an unchanged confirmed snapshot', () {
    final first = RecoveryEngine.derive(
      saved: const RecoveryState(),
      paycheck: paycheck(),
      dataset: dataset,
      now: now,
    );
    final second = RecoveryEngine.derive(
      saved: first,
      paycheck: paycheck(),
      dataset: dataset,
      now: now.add(const Duration(hours: 1)),
    );

    expect(second.history, hasLength(1));
    expect(second.history.single.id, first.history.single.id);
  });

  test('paid claim contributes to benefit claimed amount', () {
    final saved = RecoveryState(
      claimCases: [
        ClaimCase(
          id: 'claim-internet',
          paycheckItemId: 'internet',
          label: 'Internet reimbursement',
          detail: 'Bill found',
          amount: 1000,
          status: ClaimCaseStatus.paid,
          createdAt: now,
        ),
      ],
    );

    final state = RecoveryEngine.derive(
      saved: saved,
      paycheck: paycheck(),
      dataset: dataset,
      now: now,
    );

    expect(state.benefits.single.claimed, 1000);
    expect(state.benefits.single.remaining, 11000);
  });

  test('keeps a user-confirmed benefit cap and deadline', () {
    final deadline = DateTime(2026, 10, 31);
    final saved = RecoveryState(
      benefits: [
        BenefitLedgerEntry(
          id: 'internet',
          label: 'Internet reimbursement',
          annualCap: 24000,
          claimed: 0,
          resetMonth: 4,
          deadline: deadline,
          source: 'Added by you from your employer policy',
        ),
      ],
    );

    final state = RecoveryEngine.derive(
      saved: saved,
      paycheck: paycheck(),
      dataset: dataset,
      now: now,
    );

    expect(state.benefits.single.annualCap, 24000);
    expect(state.benefits.single.deadline, deadline);
    expect(
      state.benefits.single.source,
      'Added by you from your employer policy',
    );
  });

  test('sample data never creates persisted recovery records', () {
    final sample = paycheck().copyWith(usingSampleData: true);
    final state = RecoveryEngine.derive(
      saved: const RecoveryState(),
      paycheck: sample,
      dataset: dataset,
      now: now,
    );

    expect(state.claimCases, isEmpty);
    expect(state.history, isEmpty);
    expect(state.checklists, isEmpty);
  });
}
