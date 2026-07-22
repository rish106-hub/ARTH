import 'package:arth/providers/paycheck_provider.dart';
import 'package:arth/providers/user_profile_provider.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/models/payslip_tax_prefill.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/screens/s29_paycheck_shell_screen.dart';
import 'package:arth/screens/s30_tax_plan_entry_screen.dart';
import 'package:arth/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('manual evidence is kept for review and leaves sample mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(paycheckProvider.notifier)
        .addEvidence('Cult gym receipt July.pdf');
    final paycheck = container.read(paycheckProvider);

    expect(paycheck.usingSampleData, isFalse);
    expect(paycheck.evidence.first.name, 'Cult gym receipt July.pdf');
    expect(paycheck.evidence.first.statusLabel, 'REVIEW');
    expect(paycheck.evidence.first.needsAction, isTrue);
  });

  test('confirmed payslip updates persistent paycheck values', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(paycheckProvider.notifier).syncDocuments([
      TaxDocument(
        id: 'payslip-1',
        fy: '2026-27',
        documentType: 'payslip',
        originalFilename: 'July payslip.jpg',
        mimeType: 'image/jpeg',
        byteSize: 1234,
        parseStatus: 'parsed',
        parseSummary: const {},
        reviewStatus: 'reviewed',
        confirmedFields: const {
          'employeeName': 'Rishav',
          'employerName': 'Example Employer',
          'payPeriod': 'July 2026',
          'earnings': [
            {
              'label': 'Basic',
              'amount': 19333.33,
              'classification': 'basic_pay',
            },
            {
              'label': 'HRA',
              'amount': 7733.33,
              'classification': 'hra',
            },
          ],
          'deductions': [
            {
              'label': 'Professional Tax',
              'amount': 200,
              'classification': 'professional_tax',
            },
          ],
          'grossEarnings': 38766.66,
          'totalDeductions': 200,
          'netSalary': 38567,
        },
        reviewedAt: DateTime(2026, 7, 22),
      ),
    ]);

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.employeeName, 'Rishav');
    expect(paycheck.employer, 'Example Employer');
    expect(paycheck.payPeriod, 'July 2026');
    expect(paycheck.grossReceived, 38767);
    expect(paycheck.netCredited, 38567);
    expect(paycheck.otherDeductions, 200);
    expect(paycheck.items, hasLength(3));
    expect(paycheck.evidence.single.statusLabel, 'CONFIRMED');
  });

  test('confirmed payslip prefills annual tax inputs without guessing', () {
    final prefill = payslipTaxPrefillFromDocuments([
      TaxDocument(
        id: 'payslip-prefill',
        fy: '2026-27',
        documentType: 'payslip',
        originalFilename: 'July payslip.jpg',
        mimeType: 'image/jpeg',
        byteSize: 1234,
        parseStatus: 'parsed',
        parseSummary: const {},
        reviewStatus: 'reviewed',
        confirmedFields: const {
          'employerName': 'Example Employer',
          'payPeriod': 'July 2026',
          'earnings': [
            {
              'label': 'Basic',
              'amount': 19333.33,
              'classification': 'basic_pay',
            },
            {
              'label': 'HRA',
              'amount': 7733.33,
              'classification': 'hra',
            },
            {
              'label': 'Special allowance',
              'amount': 6122.30,
              'classification': 'allowance',
            },
          ],
          'deductions': [
            {
              'label': 'Professional Tax',
              'amount': 200,
              'classification': 'professional_tax',
            },
          ],
          'grossEarnings': 38766.66,
        },
        reviewedAt: DateTime(2026, 7, 22),
      ),
    ]);

    expect(prefill, isNotNull);
    expect(prefill!.annualGrossSalary, 465204);
    expect(prefill.annualBasicSalary, 231996);
    expect(prefill.annualHraReceived, 92796);
    expect(prefill.annualProfessionalTax, 2400);

    final profile = prefill.applyTo(const UserProfile(city: 'Durgapur'));
    expect(profile.employerName, 'Example Employer');
    expect(profile.hasHRA, isTrue);
    expect(profile.actualBasicSalary, 231996);
    expect(profile.actualHraReceived, 92796);
    expect(profile.actualProfessionalTax, 2400);
  });

  test('payslip annualizes over a partial-year job duration', () {
    final doc = TaxDocument(
      id: 'payslip-6mo',
      fy: '2026-27',
      documentType: 'payslip',
      originalFilename: 'July payslip.jpg',
      mimeType: 'image/jpeg',
      byteSize: 1234,
      parseStatus: 'parsed',
      parseSummary: const {},
      reviewStatus: 'reviewed',
      confirmedFields: const {
        'employerName': 'Example Employer',
        'payPeriod': 'July 2026',
        'earnings': [
          {'label': 'Basic', 'amount': 20000, 'classification': 'basic_pay'},
          {'label': 'HRA', 'amount': 8000, 'classification': 'hra'},
        ],
        'deductions': [
          {
            'label': 'Professional Tax',
            'amount': 200,
            'classification': 'professional_tax',
          },
        ],
        'grossEarnings': 28000,
      },
      reviewedAt: DateTime(2026, 7, 22),
    );

    // Default 12 months → ×12.
    final full = payslipTaxPrefillFromDocuments([doc]);
    expect(full!.annualGrossSalary, 336000);
    expect(full.annualBasicSalary, 240000);

    // 6-month job → ×6, so annual figures halve.
    final half = payslipTaxPrefillFromDocuments([doc], monthsWorked: 6);
    expect(half!.annualGrossSalary, 168000);
    expect(half.annualBasicSalary, 120000);
    expect(half.annualHraReceived, 48000);
    expect(half.annualProfessionalTax, 1200);
  });

  test('legacy payslip stored as an offer letter still updates Home', () {
    const document = TaxDocument(
      id: 'legacy-payslip',
      fy: '2026-27',
      documentType: 'offerLetter',
      originalFilename: 'salary-july.jpg',
      mimeType: 'image/jpeg',
      byteSize: 1234,
      parseStatus: 'parsed',
      parseSummary: {
        'parser': 'gemini-payslip-v1',
        'detectedDocumentType': 'payslip',
      },
      reviewStatus: 'reviewed',
      confirmedFields: {
        'employerName': 'Legacy Employer',
        'payPeriod': 'July 2026',
        'earnings': [
          {'label': 'Basic', 'amount': 20000},
        ],
        'deductions': [
          {'label': 'Professional Tax', 'amount': 200},
        ],
        'grossEarnings': 20000,
        'totalDeductions': 200,
        'netSalary': 19800,
      },
    );
    expect(document.isPayslip, isTrue);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(paycheckProvider.notifier).syncDocuments([document]);

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.employer, 'Legacy Employer');
    expect(paycheck.netCredited, 19800);
    expect(paycheck.offerLetterAdded, isFalse);
    expect(paycheck.evidence.single.statusLabel, 'CONFIRMED');
  });

  testWidgets('tax planning opens as a contained tool from You',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: '/paycheck/you',
      routes: [
        GoRoute(
          path: '/paycheck/you',
          builder: (_, __) => const PaycheckShellScreen(initialIndex: 3),
        ),
        GoRoute(
          path: '/tax-plan',
          builder: (_, __) => const TaxPlanEntryScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedTaxProfileProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('tax_plan_tool')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('tax_plan_tool')));
    await tester.pumpAndSettle();

    expect(find.text('Plan your tax.'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Housing'), findsOneWidget);
    expect(find.text('Deductions'), findsOneWidget);
    expect(find.byKey(const Key('tax_plan_start')), findsOneWidget);
    expect(find.textContaining('not generated by AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing tax planning returns to the paycheck profile',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/tax-plan',
      routes: [
        GoRoute(
          path: '/tax-plan',
          builder: (_, __) => const TaxPlanEntryScreen(),
        ),
        GoRoute(
          path: '/paycheck/you',
          builder: (_, __) => const PaycheckShellScreen(initialIndex: 3),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedTaxProfileProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tax_plan_close')));
    await tester.pumpAndSettle();

    expect(find.text('Your information'), findsOneWidget);
  });
}
