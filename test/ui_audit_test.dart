import 'package:arth/models/gap_card.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/user_account.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/auth_provider.dart';
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
import 'package:arth/screens/s11_settings_screen.dart';
import 'package:arth/screens/s12_budget_alert_screen.dart';
import 'package:arth/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final overrides = [
    userProfileProvider.overrideWith(
      () => _FixedUserProfileNotifier(sampleProfile),
    ),
    gapStateProvider.overrideWith(() => _FixedGapStateNotifier({})),
    taxResultProvider.overrideWith((ref) async => sampleResult),
    authProvider.overrideWith(
      () => _FixedAuthNotifier(_FixedAuthService(account)),
    ),
  ];

  Future<void> pumpAuditedScreen(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
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

  testWidgets(
    'major screens render without build/layout exceptions on narrow phone',
    (tester) async {
      final screens = <Widget>[
        const AuthScreen(),
        const WelcomeScreen(),
        const QuestionsScreen(),
        const GapRevealScreen(),
        const RegimeComparisonScreen(),
        const DeductionCardsScreen(),
        const DeductionDetailScreen(gap: sampleGap1),
        const ActionPlanScreen(),
        const ProgressTrackerScreen(),
        const ShareCardScreen(),
        const SettingsScreen(),
        const BudgetAlertScreen(),
      ];

      for (final screen in screens) {
        await pumpAuditedScreen(tester, screen);
      }
    },
  );
}

class _FixedUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _profile;

  _FixedUserProfileNotifier(this._profile);

  @override
  UserProfile build() => _profile;
}

class _FixedGapStateNotifier extends GapStateNotifier {
  final Map<String, bool> _state;

  _FixedGapStateNotifier(this._state);

  @override
  Map<String, bool> build() => _state;
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
