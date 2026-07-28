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

    expect(find.text('MONTHLY PLANNING INCOME'), findsOneWidget);
    expect(find.textContaining('Confirmed payslip net'), findsOneWidget);
    expect(find.byKey(const Key('paycheck_claimable_amount')), findsOneWidget);
    expect(find.byKey(const Key('open_monthly_close')), findsOneWidget);
    expect(find.text('Needs your review'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('paycheck_nav_documents')));
    await tester.pumpAndSettle();

    expect(find.text('Documents behind your pay'), findsOneWidget);
    expect(find.text('Your files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filing shows paycheck tax impact and evidence hints', (
    tester,
  ) async {
    await tester.pumpWidget(
      sampleScope(const MaterialApp(home: PaycheckShellScreen())),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('paycheck_nav_filing')));
    await tester.pumpAndSettle();

    expect(find.text('Paycheck tax impact'), findsOneWidget);
    expect(find.text('Payslip tax signals'), findsOneWidget);
    expect(find.text('Provident fund found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planning income keeps the sheet open for an invalid amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      sampleScope(const MaterialApp(home: PaycheckShellScreen())),
    );
    await tester.pump();

    await tester.tap(find.text('MONTHLY PLANNING INCOME'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Primary monthly income'),
      '',
    );
    await tester.tap(find.text('Save income'));
    await tester.pump();

    expect(find.text('Enter a monthly amount above zero.'), findsOneWidget);
    expect(find.text('Monthly planning income'), findsOneWidget);
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

  testWidgets('paycheck totals open categorized component breakdowns', (
    tester,
  ) async {
    await tester.pumpWidget(
      sampleScope(const MaterialApp(home: PaycheckShellScreen())),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Gross earnings'));
    await tester.tap(find.text('Gross earnings'));
    await tester.pumpAndSettle();

    expect(find.text('Contractual pay'), findsOneWidget);
    expect(find.text('Performance and variable pay'), findsOneWidget);
    expect(find.textContaining('Basic pay'), findsWidgets);
    expect(find.text('CALCULATION'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deductions'));
    await tester.pumpAndSettle();

    expect(find.text('Taxes'), findsOneWidget);
    expect(find.text('Retirement and social security'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Net pay').last);
    await tester.pumpAndSettle();

    expect(find.text('Net pay calculation'), findsOneWidget);
    expect(find.textContaining('] − ['), findsOneWidget);
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
