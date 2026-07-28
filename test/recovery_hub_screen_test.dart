import 'package:arth/features/recovery/models/recovery_models.dart';
import 'package:arth/features/recovery/providers/recovery_provider.dart';
import 'package:arth/features/recovery/screens/recovery_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recovery ledger renders on a small Android screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recovery = RecoveryState(
      datasetVersion: 'test-v1',
      claimCases: [
        ClaimCase(
          id: 'claim-internet',
          paycheckItemId: 'internet',
          label: 'Internet reimbursement',
          detail: 'Bill found',
          amount: 1200,
          status: ClaimCaseStatus.review,
          createdAt: DateTime(2026, 7, 28),
        ),
      ],
      benefits: [
        BenefitLedgerEntry(
          id: 'internet',
          label: 'Internet reimbursement',
          annualCap: 12000,
          claimed: 0,
          resetMonth: 4,
          deadline: DateTime(2027, 3, 31),
          source: 'Added by you from your employer policy',
        ),
      ],
      history: [
        ReconciliationSnapshot(
          id: 'july',
          payPeriod: 'July 2026',
          createdAt: DateTime(2026, 7, 28),
          promised: 50000,
          grossPaid: 48000,
          netPaid: 45000,
          salaryCredit: 45000,
          delta: -2000,
          itemAmounts: const {'internet': 1200},
          itemLabels: const {'internet': 'Internet reimbursement'},
          evidenceIds: const ['payslip-july'],
        ),
      ],
      checklists: const [
        PaydayChecklist(
          monthKey: '2026-07',
          creditFound: true,
          payslipChecked: true,
          claimItemsReviewed: false,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryProvider.overrideWith(
            () => _StubRecoveryNotifier(recovery),
          ),
        ],
        child: const MaterialApp(home: RecoveryHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Money recovery'), findsOneWidget);
    expect(find.text('PAYDAY CHECK'), findsOneWidget);
    expect(find.text('Claim cases'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Benefits'), 250);
    expect(find.text('Benefits'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Monthly history'), 250);
    expect(find.text('Monthly history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StubRecoveryNotifier extends RecoveryNotifier {
  _StubRecoveryNotifier(this.value);

  final RecoveryState value;

  @override
  Future<RecoveryState> build() async => value;
}
