import 'package:arth/models/gap_card.dart';
import 'package:arth/models/money_plan.dart';
import 'package:arth/models/account_profile.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/models/tax_readiness.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/user_account.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/account_profile_provider.dart';
import 'package:arth/providers/auth_provider.dart';
import 'package:arth/providers/money_plan_provider.dart';
import 'package:arth/providers/tax_document_provider.dart';
import 'package:arth/providers/tax_readiness_provider.dart';
import 'package:arth/providers/tax_result_provider.dart';
import 'package:arth/providers/user_profile_provider.dart';
import 'package:arth/screens/s00_auth_screen.dart';
import 'package:arth/screens/s02_welcome_screen.dart';
import 'package:arth/screens/s03_questions_screen.dart';
import 'package:arth/screens/s04_gap_reveal_screen.dart';
import 'package:arth/screens/s05_regime_comparison_screen.dart';
import 'package:arth/screens/s06_deduction_cards_screen.dart';
import 'package:arth/screens/s07_deduction_detail_screen.dart';
import 'package:arth/screens/s08_action_plan_screen.dart';
import 'package:arth/screens/s09_progress_tracker_screen.dart';
import 'package:arth/screens/s10_share_card_screen.dart';
import 'package:arth/screens/s12_budget_alert_screen.dart';
import 'package:arth/screens/s13_discover_screen.dart';
import 'package:arth/screens/s14_profile_screen.dart';
import 'package:arth/screens/s15_document_checklist_screen.dart';
import 'package:arth/screens/s16_ais_guide_screen.dart';
import 'package:arth/screens/s17_help_center_screen.dart';
import 'package:arth/screens/s18_tax_dossier_screen.dart';
import 'package:arth/screens/s20_accuracy_coach_screen.dart';
import 'package:arth/screens/s21_tax_simulator_screen.dart';
import 'package:arth/screens/s22_tax_story_screen.dart';
import 'package:arth/screens/s23_tax_calendar_screen.dart';
import 'package:arth/screens/s24_control_room_demo_screen.dart';
import 'package:arth/screens/s25_money_setup_screen.dart';
import 'package:arth/screens/s26_income_screen.dart';
import 'package:arth/screens/s27_money_plan_screen.dart';
import 'package:arth/services/auth_service.dart';
import 'package:arth/services/backend_sync_service.dart';
import 'package:arth/theme/app_theme.dart';
import 'package:arth/widgets/question_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  final sampleProfile = const UserProfile(
    name: 'Audit User',
    email: 'audit@example.com',
    annualCTC: 1800000,
    employmentType: EmploymentType.salaried,
    city: 'Delhi',
    isMetroCity: true,
    paysRent: true,
    monthlyRent: 35000,
    hasHRA: true,
    invested80C: 70000,
    hasHomeLoan: true,
    propertyType: PropertyType.selfOccupied,
    homeLoanInterest: 200000,
    hasNPS: true,
    npsExtraContribution: 50000,
    hasHealthInsuranceSelf: true,
    hasHealthInsuranceParents: true,
    parentsAbove60: true,
    hasEducationLoan: true,
    educationLoanRepaymentYear: 3,
    educationLoanInterest: 60000,
    hasDonations: true,
    donationAmount: 25000,
    ageGroup: AgeGroup.age30to45,
  );

  const sampleGap1 = GapCard(
    id: 'T08_section24b_home_loan',
    section: 'Section 24(b)',
    title: 'Home Loan Interest',
    shortDesc: 'Up to ₹2 lakh deduction',
    message: 'Claim your home loan interest up to ₹2 lakh under Section 24(b).',
    gapAmount: 200000,
    difficulty: GapDifficulty.easy,
    difficultyLabel: 'Easy (interest certificate)',
    deadline: '31 July 2026',
    actions: [
      GapAction(label: 'Get Loan Statement', url: 'https://example.com'),
    ],
    colorHex: 'F5C842',
  );

  const sampleGap2 = GapCard(
    id: 'T01_80C_gap',
    section: '80C',
    title: 'Investments Gap',
    shortDesc: 'Mutual Funds, PPF, LIC',
    message: 'You can invest more in ELSS or PPF to fully use 80C.',
    gapAmount: 80000,
    difficulty: GapDifficulty.easy,
    difficultyLabel: 'Easy (20 min online)',
    deadline: '31 March 2026',
    actions: [GapAction(label: 'Open ELSS SIP', url: 'https://example.com')],
    colorHex: 'FF9800',
  );

  const sampleGap3 = GapCard(
    id: 'T07_80E_education_loan',
    section: '80E',
    title: 'Education Loan Interest',
    shortDesc: 'Entire interest, no cap',
    message: 'Your education loan interest is fully deductible under 80E.',
    gapAmount: 60000,
    difficulty: GapDifficulty.easy,
    difficultyLabel: 'Easy (interest certificate)',
    deadline: '31 July 2026',
    actions: [
      GapAction(label: 'Get Interest Certificate', url: 'https://example.com'),
    ],
    colorHex: '26A69A',
  );

  const sampleGap80TTA = GapCard(
    id: 'T09_80TTA',
    section: '80TTA',
    title: 'Savings Account Interest',
    shortDesc: 'Up to ₹10,000 tax-free',
    message: 'Your savings account interest up to ₹10,000 is tax-free.',
    gapAmount: 10000,
    difficulty: GapDifficulty.easy,
    difficultyLabel: 'Easy (auto-claimed on ITR)',
    deadline: '31 July 2026',
    actions: [
      GapAction(label: 'Claim on ITR Portal', url: 'https://example.com'),
    ],
    colorHex: '26A69A',
  );

  final sampleResult = const TaxResult(
    oldRegimeTax: 272220,
    newRegimeTax: 169000,
    oldRegimeTaxableIncome: 1697500,
    newRegimeTaxableIncome: 1725000,
    totalDeductionsOld: 102500,
    betterRegime: TaxRegime.newRegime,
    regimeSavings: 103220,
    gaps: [sampleGap1, sampleGap2, sampleGap3],
    totalGapAmount: 340000,
    gapCount: 3,
  );

  final account = UserAccount(
    name: 'Audit User',
    email: 'audit@example.com',
    createdAt: DateTime(2026, 1, 1),
    uid: 'audit-uid',
  );

  final accountProfile = AccountProfile(
    user: account,
    pan: const PanVaultStatus(present: false),
  );

  const sampleDocument = TaxDocument(
    id: 'doc-1',
    fy: '2026-27',
    documentType: 'form16',
    originalFilename: 'form16.pdf',
    mimeType: 'application/pdf',
    byteSize: 2048,
    parseStatus: 'needs_confirmation',
    parseSummary: {
      'insight': 'Form 16 text parsed. Review and confirm these values.',
      'extractedFields': {
        'employerTan': 'ABCD12345E',
        'grossSalary': 1800000,
      },
    },
    tags: ['salary'],
  );

  const sampleMoneyPlan = MoneyPlan(
    annualFixedPay: 3000000,
    annualVariablePay: 300000,
    annualEquityPay: 600000,
    monthlyTakeHome: 180000,
    monthlyCommitments: 70000,
    monthlyInvesting: 40000,
    liquidSavings: 500000,
    primaryGoalName: 'Home deposit',
    primaryGoalTarget: 2000000,
    primaryGoalSaved: 500000,
  );

  final overrides = [
    userProfileProvider.overrideWith(
      () => _FixedUserProfileNotifier(sampleProfile),
    ),
    completedTaxProfileProvider.overrideWith((ref) async => true),
    accountProfileProvider.overrideWith(
      () => _FixedAccountProfileNotifier(accountProfile),
    ),
    gapStateProvider.overrideWith(() => _FixedGapStateNotifier({})),
    documentChecklistProvider.overrideWith(
      () => _FixedDocumentChecklistNotifier({}),
    ),
    taxDocumentProvider.overrideWith(
      () => _FixedTaxDocumentNotifier(const [sampleDocument]),
    ),
    taxResultProvider.overrideWith((ref) async => sampleResult),
    authProvider.overrideWith(
      () => _FixedAuthNotifier(_FixedAuthService(account)),
    ),
    moneyPlanProvider.overrideWith(
      () => _FixedMoneyPlanNotifier(sampleMoneyPlan),
    ),
  ];

  overridesWithChecklist(Map<String, bool> checklist) => [
        userProfileProvider.overrideWith(
          () => _FixedUserProfileNotifier(sampleProfile),
        ),
        completedTaxProfileProvider.overrideWith((ref) async => true),
        accountProfileProvider.overrideWith(
          () => _FixedAccountProfileNotifier(accountProfile),
        ),
        gapStateProvider.overrideWith(() => _FixedGapStateNotifier({})),
        documentChecklistProvider.overrideWith(
          () => _FixedDocumentChecklistNotifier(checklist),
        ),
        taxDocumentProvider.overrideWith(
          () => _FixedTaxDocumentNotifier(const []),
        ),
        taxResultProvider.overrideWith((ref) async => sampleResult),
        authProvider.overrideWith(
          () => _FixedAuthNotifier(_FixedAuthService(account)),
        ),
        moneyPlanProvider.overrideWith(
          () => _FixedMoneyPlanNotifier(sampleMoneyPlan),
        ),
      ];

  Future<void> pumpAuditedScreen(
    WidgetTester tester,
    Widget child, {
    customOverrides,
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: customOverrides ?? overrides,
        child: MaterialApp(theme: AppTheme.light, home: child),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final errors = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      errors.add(exception!);
    }
    expect(errors, isEmpty, reason: 'Screen failed: ${child.runtimeType}');
  }

  Future<void> pumpReducedMotionScreen(
    WidgetTester tester,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final errors = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      errors.add(exception!);
    }
    expect(
      errors,
      isEmpty,
      reason: 'Reduced-motion screen failed: ${child.runtimeType}',
    );
  }

  testWidgets(
    'major screens render without build/layout exceptions on narrow phone',
    (tester) async {
      final screens = <Widget>[
        const AuthScreen(),
        const DiscoverScreen(),
        const WelcomeScreen(),
        const MoneySetupScreen(),
        const IncomeScreen(),
        const MoneyPlanScreen(),
        const QuestionsScreen(),
        const GapRevealScreen(),
        const RegimeComparisonScreen(),
        const DeductionCardsScreen(),
        const DeductionDetailScreen(gap: sampleGap1),
        const ActionPlanScreen(),
        const ProgressTrackerScreen(),
        const ShareCardScreen(),
        const ProfileScreen(),
        const DocumentChecklistScreen(),
        const AisGuideScreen(),
        const HelpCenterScreen(),
        const TaxDossierScreen(),
        const AccuracyCoachScreen(),
        const TaxSimulatorScreen(),
        const TaxStoryScreen(),
        const TaxCalendarScreen(),
        const BudgetAlertScreen(),
        const ControlRoomDemoScreen(),
      ];

      for (final screen in screens) {
        await pumpAuditedScreen(tester, screen);
      }
    },
  );

  testWidgets('diagnostic keeps one question and one chapter in focus', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const QuestionsScreen());

    expect(find.image(const AssetImage('assets/images/tax_journey.png')),
        findsNothing);
    expect(find.text('Income profile'), findsOneWidget);
    expect(find.text('First, the shape of your income.'), findsOneWidget);
    expect(find.text('1 of 12'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('profile clear-data action opens confirmation dialog', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const ProfileScreen());

    await tester.scrollUntilVisible(
      find.text('Clear all data'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Clear all data'));
    await tester.pumpAndSettle();

    expect(find.text('Clear all data?'), findsOneWidget);
    expect(
      find.text(
          'This clears your money baseline, tax profile, calculations, progress, and PAN vault data.'),
      findsOneWidget,
    );
    expect(find.text('Clear data'), findsOneWidget);
  });

  testWidgets('auth supports premium create and sign-in modes on narrow phone',
      (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const AuthScreen());

    expect(find.text('Give your income a job.'), findsOneWidget);
    expect(find.text('A first plan takes about 3 minutes.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('welcome explains the product and starts the plan directly', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const WelcomeScreen());

    expect(find.text('Know what your\nmoney needs next.'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Commit'), findsOneWidget);
    expect(find.text('Decide'), findsOneWidget);
    expect(find.text('Build my money baseline'), findsOneWidget);
    expect(find.textContaining('DigiLocker'), findsNothing);
  });

  testWidgets('tax cockpit shows next action and future modules', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const GapRevealScreen());

    expect(find.text('Tax Cockpit'), findsOneWidget);
    expect(find.text('NEXT BEST ACTION'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('EVERYTHING TAX'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('EVERYTHING TAX'), findsOneWidget);
    expect(find.text('Tax reminders'), findsOneWidget);
  });

  testWidgets('regime guidance follows useful income decision order', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const RegimeComparisonScreen());
    await tester.pumpAndSettle();

    expect(find.text('General Guidance by Income'), findsOneWidget);
    expect(find.text('Up to ₹12.75L salary'), findsOneWidget);
    expect(find.text('₹12.75L – ₹24L'), findsOneWidget);
    expect(find.text('₹24L – ₹50L'), findsOneWidget);
    expect(find.text('Above ₹50L'), findsOneWidget);
    expect(find.text('Usually New'), findsOneWidget);

    final guidanceTop = tester
        .getTopLeft(
          find.text('General Guidance by Income'),
        )
        .dy;
    final deductionTop = tester
        .getTopLeft(
          find.text('Old Regime Deduction Stack'),
        )
        .dy;
    expect(guidanceTop, lessThan(deductionTop));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('browse-first discover works before diagnostic', (tester) async {
    final browseOverrides = [
      userProfileProvider.overrideWith(
        () => _FixedUserProfileNotifier(const UserProfile()),
      ),
      completedTaxProfileProvider.overrideWith((ref) async => false),
      accountProfileProvider.overrideWith(
        () => _FixedAccountProfileNotifier(accountProfile),
      ),
      documentChecklistProvider.overrideWith(
        () => _FixedDocumentChecklistNotifier({}),
      ),
      taxDocumentProvider.overrideWith(
        () => _FixedTaxDocumentNotifier(const [sampleDocument]),
      ),
      authProvider.overrideWith(
        () => _FixedAuthNotifier(_FixedAuthService(account)),
      ),
      moneyPlanProvider.overrideWith(
        () => _FixedMoneyPlanNotifier(const MoneyPlan()),
      ),
    ];

    await pumpAuditedScreen(
      tester,
      const DiscoverScreen(),
      customOverrides: browseOverrides,
    );

    expect(find.text('Your money has no working plan yet.'), findsOneWidget);
    expect(find.text('Build your money baseline'), findsOneWidget);
    expect(find.text('Set up my plan'), findsOneWidget);
    expect(find.text('Explore ARTH'), findsNothing);
    expect(find.text('Tax Dossier'), findsNothing);
  });

  testWidgets('Today stays focused on one status and one next move', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const DiscoverScreen());
    await tester.pumpAndSettle();

    expect(find.text('ARTH'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(
        find.textContaining('is still unassigned this month.'), findsOneWidget);
    expect(find.text('Move your primary goal forward'), findsOneWidget);
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('Quick actions'), findsNothing);
    expect(find.text('Explore ARTH'), findsNothing);
  });

  testWidgets('Income and Plan share one money baseline', (tester) async {
    await pumpAuditedScreen(tester, const IncomeScreen());
    expect(find.text('₹ 39 L'), findsOneWidget);
    expect(find.textContaining('₹ 1.8 L reaches you'), findsOneWidget);
    expect(find.text('Fixed pay'), findsOneWidget);
    expect(find.text('Variable pay'), findsOneWidget);
    expect(find.text('Equity compensation'), findsOneWidget);

    await pumpAuditedScreen(tester, const MoneyPlanScreen());
    expect(find.text('₹ 70K'), findsOneWidget);
    expect(find.text('Move your primary goal forward'), findsOneWidget);
  });

  testWidgets('purchase scenario shows the effect on liquid runway', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const MoneyPlanScreen());
    await tester.scrollUntilVisible(
      find.text('Test a one-time purchase'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Test a one-time purchase'));
    await tester.pumpAndSettle();

    expect(find.text('Test a purchase'), findsOneWidget);
    expect(find.text('Savings left'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(
      find.textContaining('This does not judge the purchase'),
      findsOneWidget,
    );
  });

  testWidgets('Help Center shows contact actions and support details', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const HelpCenterScreen());

    expect(find.text('Rishav Dewan'), findsOneWidget);
    expect(find.text('rishavdewan10@gmail.com'), findsOneWidget);
    expect(find.text('9749452397'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Data/privacy help'), findsOneWidget);
    expect(find.text('Demo walkthrough'), findsOneWidget);
  });

  testWidgets('Document Vault renders empty, partial, and complete states', (
    tester,
  ) async {
    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({}),
    );
    expect(find.textContaining('proof items still need attention.'),
        findsOneWidget);
    expect(find.textContaining('DigiLocker'), findsNothing);
    expect(find.text('Form 16'), findsOneWidget);

    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({
        taxDocumentItems[0].id: true,
        taxDocumentItems[1].id: true,
      }),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator).first,
          )
          .value,
      0.25,
    );

    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({
        for (final item in taxDocumentItems) item.id: true,
      }),
    );
    expect(find.text('Your proof checklist is complete.'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator).first,
          )
          .value,
      1,
    );
  });

  testWidgets('Document Vault upload sheet stays compact on 320px', (
    tester,
  ) async {
    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({}),
    );

    await tester.tap(find.byTooltip('Upload Form 16'));
    await tester.pumpAndSettle();

    expect(find.text('Upload Form 16'), findsOneWidget);
    expect(
      find.text('PDF · JPG · PNG   Maximum 8 MB'),
      findsOneWidget,
    );
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    final chooseFileButton = find.widgetWithText(ElevatedButton, 'Choose file');
    expect(tester.getSize(chooseFileButton).height, lessThanOrEqualTo(60));
  });

  testWidgets('AIS guide is visible without asking for PAN', (tester) async {
    await pumpAuditedScreen(tester, const AisGuideScreen());

    expect(find.text('AIS & 26AS guide'), findsOneWidget);
    expect(find.textContaining('ARTH does not fetch AIS'), findsOneWidget);
    expect(find.textContaining('Enter PAN'), findsNothing);
  });

  testWidgets('profile PAN vault educates, validates, and masks display', (
    tester,
  ) async {
    final maskedProfile = AccountProfile(
      user: account,
      pan: const PanVaultStatus(
        present: true,
        maskedPan: '•••••1234F',
        consentVersion: 'pan-v1',
      ),
    );
    await pumpAuditedScreen(
      tester,
      const ProfileScreen(),
      customOverrides: [
        userProfileProvider.overrideWith(
          () => _FixedUserProfileNotifier(sampleProfile),
        ),
        completedTaxProfileProvider.overrideWith((ref) async => true),
        accountProfileProvider.overrideWith(
          () => _FixedAccountProfileNotifier(maskedProfile),
        ),
        gapStateProvider.overrideWith(() => _FixedGapStateNotifier({})),
        documentChecklistProvider.overrideWith(
          () => _FixedDocumentChecklistNotifier({}),
        ),
        taxDocumentProvider.overrideWith(
          () => _FixedTaxDocumentNotifier(const [sampleDocument]),
        ),
        taxResultProvider.overrideWith((ref) async => sampleResult),
        authProvider.overrideWith(
          () => _FixedAuthNotifier(_FixedAuthService(account)),
        ),
      ],
    );

    expect(find.text('PAN Vault'), findsOneWidget);
    expect(find.textContaining('•••••1234F'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Update PAN'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Update PAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save PAN securely'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 10-character PAN'), findsOneWidget);
  });

  testWidgets('diagnostic back from edit mode returns to profile, not welcome',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: '/questions',
      routes: [
        GoRoute(
            path: '/questions', builder: (_, __) => const QuestionsScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    expect(find.text('You'), findsWidgets);
    expect(find.text('Skip story and answer questions'), findsNothing);
  });

  testWidgets(
    'diagnostic completion refreshes stale completion cache and opens cockpit',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final complete = ValueNotifier(false);
      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith(
            () => _CompletingUserProfileNotifier(sampleProfile, complete),
          ),
          completedTaxProfileProvider.overrideWith((ref) async {
            return complete.value;
          }),
          taxResultProvider.overrideWith((ref) async {
            final isComplete =
                await ref.watch(completedTaxProfileProvider.future);
            if (!isComplete) throw StateError('tax profile incomplete');
            return sampleResult;
          }),
          backendSyncServiceProvider
              .overrideWithValue(_NoopBackendSyncService()),
          accountProfileProvider.overrideWith(
            () => _FixedAccountProfileNotifier(accountProfile),
          ),
          gapStateProvider.overrideWith(() => _FixedGapStateNotifier({})),
          documentChecklistProvider.overrideWith(
            () => _FixedDocumentChecklistNotifier({}),
          ),
          taxDocumentProvider.overrideWith(
            () => _FixedTaxDocumentNotifier(const [sampleDocument]),
          ),
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_FixedAuthService(account)),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(completedTaxProfileProvider.future), isFalse);

      final router = GoRouter(
        initialLocation: '/questions',
        routes: [
          GoRoute(
            path: '/questions',
            builder: (_, __) => const QuestionsScreen(),
          ),
          GoRoute(
            path: '/gap-reveal',
            builder: (_, __) => const GapRevealScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapContinue() async {
        final continueButton = find.widgetWithText(
          ElevatedButton,
          'Continue',
        );
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
      }

      Future<void> tapChoice(String label) async {
        final choice = find.text(label).first;
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
      }

      await tapContinue(); // CTC
      await tapChoice('Salaried Employee');
      await tapChoice('Delhi');
      await tapContinue(); // rent amount
      await tapChoice('Yes, HRA is in my salary');
      await tapContinue(); // 80C
      await tapContinue(); // home loan
      await tapContinue(); // NPS
      await tapContinue(); // health insurance
      await tapContinue(); // education loan
      await tapContinue(); // donations

      final ageChoice = find.text('30 – 45');
      await tester.ensureVisible(ageChoice);
      await tester.tap(ageChoice);
      await tester.pumpAndSettle();

      expect(find.textContaining('Deduction opportunity'), findsOneWidget);
      expect(
        find.text('Could not build your tax cockpit. Please try again.'),
        findsNothing,
      );
    },
  );

  testWidgets('home-loan property chips do not overflow on 320px phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: SelectChip(
                    label: 'Self-occupied',
                    selected: true,
                    fullWidth: true,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectChip(
                    label: 'Let out / Rented',
                    selected: false,
                    fullWidth: true,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final errors = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      errors.add(exception!);
    }
    expect(errors, isEmpty);
  });

  testWidgets('80TTA difficulty label is not truncated to one line', (
    tester,
  ) async {
    await pumpAuditedScreen(
      tester,
      const DeductionDetailScreen(gap: sampleGap80TTA),
    );

    final labelFinder = find.text('Easy (auto-claimed on ITR)');
    expect(labelFinder, findsOneWidget);
    final label = tester.widget<Text>(labelFinder);
    expect(label.maxLines, isNull);
    expect(label.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('Today decision and primary navigation open the right routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Widget target(String label) => Scaffold(body: Center(child: Text(label)));
    final router = GoRouter(
      initialLocation: '/discover',
      routes: [
        GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
        GoRoute(path: '/income', builder: (_, __) => target('income')),
        GoRoute(path: '/plan', builder: (_, __) => target('plan')),
        GoRoute(path: '/profile', builder: (_, __) => target('profile')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Open goal plan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open goal plan'));
    await tester.pumpAndSettle();
    expect(find.text('plan'), findsOneWidget);
    router.go('/discover');
    await tester.pumpAndSettle();

    final navigationCases = <IconData, String>{
      Icons.payments_outlined: 'income',
      Icons.route_outlined: 'plan',
      Icons.person_outline_rounded: 'profile',
    };
    for (final entry in navigationCases.entries) {
      await tester.tap(find.byIcon(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      router.go('/discover');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('reduced-motion mode keeps navigation calm on narrow phone', (
    tester,
  ) async {
    await pumpReducedMotionScreen(tester, const ProgressTrackerScreen());

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}

class _FixedUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _profile;
  final bool _complete;

  _FixedUserProfileNotifier(this._profile, {bool complete = true})
      : _complete = complete;

  @override
  UserProfile build() => _profile;

  @override
  Future<bool> isOnboardingComplete() async => _complete;

  @override
  Future<void> restoreDraft(UserProfile profile) async {
    state = profile;
  }
}

class _CompletingUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _profile;
  final ValueNotifier<bool> _complete;

  _CompletingUserProfileNotifier(this._profile, this._complete);

  @override
  UserProfile build() => _profile;

  @override
  void updateField(UserProfile Function(UserProfile) updater) {
    state = updater(state);
  }

  @override
  Future<void> save() async {
    _complete.value = true;
  }

  @override
  Future<bool> isOnboardingComplete() async => _complete.value;

  @override
  Future<void> restoreDraft(UserProfile profile) async {
    state = profile;
  }
}

class _FixedGapStateNotifier extends GapStateNotifier {
  final Map<String, bool> _state;

  _FixedGapStateNotifier(this._state);

  @override
  Map<String, bool> build() => _state;
}

class _FixedDocumentChecklistNotifier extends DocumentChecklistNotifier {
  final Map<String, bool> _state;

  _FixedDocumentChecklistNotifier(this._state);

  @override
  Map<String, bool> build() => _state;

  @override
  Future<void> setReady(String id, bool ready) async {
    state = {...state, id: ready};
  }
}

class _FixedTaxDocumentNotifier extends TaxDocumentNotifier {
  final List<TaxDocument> _documents;

  _FixedTaxDocumentNotifier(this._documents);

  @override
  Future<List<TaxDocument>> build() async => _documents;

  @override
  Future<void> refresh() async {
    state = AsyncData(_documents);
  }
}

class _FixedAuthService extends AuthService {
  final UserAccount? _account;

  _FixedAuthService(this._account);

  @override
  Future<UserAccount?> loadAccount() async => _account;

  @override
  Future<void> saveAccount(UserAccount account) async {}

  @override
  Future<void> clearAccount() async {}
}

class _FixedMoneyPlanNotifier extends MoneyPlanNotifier {
  final MoneyPlan _plan;

  _FixedMoneyPlanNotifier(this._plan);

  @override
  Future<MoneyPlan> build() async => _plan;

  @override
  Future<void> save(MoneyPlan plan) async {
    state = AsyncData(plan);
  }

  @override
  Future<void> clear() async {
    state = const AsyncData(MoneyPlan());
  }
}

class _NoopBackendSyncService extends BackendSyncService {
  @override
  Future<void> syncTaxResult(TaxResult result) async {}
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(super.service);
}

class _FixedAccountProfileNotifier extends AccountProfileNotifier {
  final AccountProfile? _profile;

  _FixedAccountProfileNotifier(this._profile);

  @override
  Future<AccountProfile?> build() async => _profile;
}
