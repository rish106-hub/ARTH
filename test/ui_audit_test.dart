import 'package:arth/models/gap_card.dart';
import 'package:arth/models/account_profile.dart';
import 'package:arth/models/tax_readiness.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/user_account.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/account_profile_provider.dart';
import 'package:arth/providers/auth_provider.dart';
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
import 'package:arth/services/auth_service.dart';
import 'package:arth/widgets/question_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  final sampleProfile = UserProfile(
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

  final sampleResult = TaxResult(
    oldRegimeTax: 272220,
    newRegimeTax: 169000,
    oldRegimeTaxableIncome: 1697500,
    newRegimeTaxableIncome: 1725000,
    totalDeductionsOld: 102500,
    betterRegime: TaxRegime.newRegime,
    regimeSavings: 103220,
    gaps: const [sampleGap1, sampleGap2, sampleGap3],
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
    taxResultProvider.overrideWith((ref) async => sampleResult),
    authProvider.overrideWith(
      () => _FixedAuthNotifier(_FixedAuthService(account)),
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
        taxResultProvider.overrideWith((ref) async => sampleResult),
        authProvider.overrideWith(
          () => _FixedAuthNotifier(_FixedAuthService(account)),
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
        child: MaterialApp(home: child),
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
        const BudgetAlertScreen(),
      ];

      for (final screen in screens) {
        await pumpAuditedScreen(tester, screen);
      }
    },
  );

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
          'This wipes tax profile, calculations, progress, and PAN vault data from ARTH servers.'),
      findsOneWidget,
    );
    expect(find.text('Clear data'), findsOneWidget);
  });

  testWidgets('auth supports premium create and sign-in modes on narrow phone',
      (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const AuthScreen());

    expect(find.text('Enter your tax intelligence vault.'), findsOneWidget);
    expect(find.text('PAN optional later'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('welcome narrative exposes trust-first onboarding story', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const WelcomeScreen());

    expect(find.text('Find money your salary already earned.'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('No PAN. No ITR upload. No document dragnet.'),
        findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Get a cockpit, not a spreadsheet.'), findsOneWidget);
    expect(find.text('Start diagnostic'), findsOneWidget);
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
      authProvider.overrideWith(
        () => _FixedAuthNotifier(_FixedAuthService(account)),
      ),
    ];

    await pumpAuditedScreen(
      tester,
      const DiscoverScreen(),
      customOverrides: browseOverrides,
    );

    expect(find.text('Start diagnostic'), findsOneWidget);
    expect(find.text('Private Tax Readiness Cockpit'), findsOneWidget);
    expect(find.text('Document checklist'), findsOneWidget);
    expect(find.text('AIS & 26AS guide'), findsOneWidget);
  });

  testWidgets('Tax OS home renders readiness cockpit on 320px', (
    tester,
  ) async {
    await pumpAuditedScreen(tester, const DiscoverScreen());

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Private Tax Readiness Cockpit'), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('EVERYTHING TAX'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Tax Dossier'), findsOneWidget);
    expect(find.text('Help Center'), findsOneWidget);
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
  });

  testWidgets('Document checklist renders empty, partial, and complete states',
      (
    tester,
  ) async {
    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({}),
    );
    expect(find.text('0/8 ready'), findsOneWidget);
    expect(find.text('Form 16'), findsOneWidget);

    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({
        taxDocumentItems[0].id: true,
        taxDocumentItems[1].id: true,
      }),
    );
    expect(find.text('2/8 ready'), findsOneWidget);

    await pumpAuditedScreen(
      tester,
      const DocumentChecklistScreen(),
      customOverrides: overridesWithChecklist({
        for (final item in taxDocumentItems) item.id: true,
      }),
    );
    expect(find.text('8/8 ready'), findsOneWidget);
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

    expect(find.text('Account and privacy'), findsOneWidget);
    expect(find.text('Skip story and answer questions'), findsNothing);
  });

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

  testWidgets('reduced-motion mode keeps navigation calm on narrow phone', (
    tester,
  ) async {
    await pumpReducedMotionScreen(tester, const ProgressTrackerScreen());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
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

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(super.service);
}

class _FixedAccountProfileNotifier extends AccountProfileNotifier {
  final AccountProfile? _profile;

  _FixedAccountProfileNotifier(this._profile);

  @override
  Future<AccountProfile?> build() async => _profile;
}
