import 'package:arth/models/paycheck.dart';
import 'package:arth/providers/paycheck_provider.dart';
import 'package:arth/screens/s29_paycheck_shell_screen.dart';
import 'package:arth/theme/paycheck_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderScope sampleScope(Widget child) => ProviderScope(
        overrides: [
          paycheckProvider.overrideWith(SamplePaycheckNotifier.new),
        ],
        child: child,
      );

  test('demo paycheck separates received, claimable and pending money', () {
    expect(demoPaycheck.claimableNow, 6400);
    expect(demoPaycheck.pendingAmount, 7500);
    expect(demoPaycheck.reconciliationPercent, 97);
    expect(
      demoPaycheck.items
          .where((item) => item.status == PaycheckItemStatus.claimable)
          .length,
      2,
    );
  });

  test('paycheck typography uses the bundled Anek family', () {
    expect(PaycheckType.body().fontFamily, 'Anek');
    expect(PaycheckType.display().fontFamily, 'Anek');
    expect(PaycheckType.utility().fontSize, greaterThanOrEqualTo(12));
  });

  testWidgets('paycheck home and evidence tabs render on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      sampleScope(const MaterialApp(home: PaycheckShellScreen())),
    );
    await tester.pump();

    expect(find.byKey(const Key('paycheck_claimable_amount')), findsOneWidget);
    expect(find.text('Needs your review'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('paycheck_nav_evidence')));
    await tester.pumpAndSettle();

    expect(find.text('Documents behind your pay'), findsOneWidget);
    expect(find.text('Your files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('claim pack can be prepared with explicit approval', (
    tester,
  ) async {
    await tester.pumpWidget(
      sampleScope(const MaterialApp(home: PaycheckShellScreen())),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Internet reimbursement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internet reimbursement'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare claim'), findsOneWidget);

    await tester.tap(find.text('Prepare claim pack'));
    await tester.pumpAndSettle();
    expect(find.text('READY'), findsOneWidget);
  });

  testWidgets('confirmed payslip replaces empty home copy on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paycheckProvider.overrideWith(ConfirmedPayslipNotifier.new),
        ],
        child: const MaterialApp(home: PaycheckShellScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Your July 2026 pay is ready'), findsOneWidget);
    expect(find.textContaining('38,567'), findsWidgets);
    expect(find.textContaining('38,767'), findsWidgets);
    expect(find.textContaining('Two benefits'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty paycheck opens Evidence from the primary action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paycheckProvider.overrideWith(EmptyPaycheckNotifier.new),
        ],
        child: const MaterialApp(home: PaycheckShellScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Add your first payslip'), findsOneWidget);
    expect(find.byKey(const Key('add_first_payslip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_first_payslip')));
    await tester.pumpAndSettle();

    expect(find.text('Documents behind your pay'), findsOneWidget);
    expect(find.byKey(const Key('add_paycheck_evidence')), findsOneWidget);
  });
}

class SamplePaycheckNotifier extends PaycheckNotifier {
  @override
  PaycheckState build() => demoPaycheck;
}

class ConfirmedPayslipNotifier extends PaycheckNotifier {
  @override
  PaycheckState build() => emptyPaycheck.copyWith(
        employeeName: 'Rishav',
        employer: 'Example Employer',
        payPeriod: 'July 2026',
        grossReceived: 38767,
        netCredited: 38567,
        otherDeductions: 200,
      );
}

class EmptyPaycheckNotifier extends PaycheckNotifier {
  @override
  PaycheckState build() => emptyPaycheck;
}
