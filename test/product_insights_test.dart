import 'package:arth/models/gap_card.dart';
import 'package:arth/models/product_insights.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/tax_rule_set.dart';
import 'package:arth/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next-best-action guides incomplete users to diagnostic', () {
    final action = buildNextBestAction(
      diagnosticComplete: false,
      documentPercent: 0,
    );

    expect(action.route, '/questions');
    expect(action.cta, 'Start diagnostic');
  });

  test('next-best-action prioritizes accuracy before documents', () {
    final action = buildNextBestAction(
      diagnosticComplete: true,
      documentPercent: 0,
      result: _resultWithAssumption(),
    );

    expect(action.route, '/accuracy-coach');
    expect(action.title, 'Improve calculation accuracy');
  });

  test('accuracy tasks are derived from existing profile gaps', () {
    final profile = const UserProfile(
      annualCTC: 1800000,
      employmentType: EmploymentType.salaried,
      paysRent: true,
      hasHRA: true,
      hasHealthInsuranceSelf: true,
      hasDonations: true,
    );

    final codes = buildAccuracyTasks(profile).map((task) => task.code);

    expect(codes, contains('basic_salary'));
    expect(codes, contains('hra_received'));
    expect(codes, contains('80d_self'));
    expect(codes, contains('donation_rate'));
  });

  test('calendar exposes readiness and handoff routes', () {
    final routes = taxCalendarItems('FY 2026-27').map((item) => item.route);

    expect(routes, contains('/documents'));
    expect(routes, contains('/accuracy-coach'));
    expect(routes, contains('/filing-assistant'));
  });
}

TaxResult _resultWithAssumption() {
  return const TaxResult(
    ruleSetId: 'fy_2026_27',
    ruleSetLabel: 'FY2026-27 Planning',
    assessmentYear: 'AY 2027-28',
    calculationMode: CalculationMode.planning,
    oldRegimeTax: 220000,
    newRegimeTax: 180000,
    oldRegimeTaxableIncome: 1600000,
    newRegimeTaxableIncome: 1725000,
    totalDeductionsOld: 125000,
    betterRegime: TaxRegime.newRegime,
    regimeSavings: 40000,
    gaps: [
      GapCard(
        id: 'T01_80C_gap',
        section: '80C',
        title: '80C gap',
        shortDesc: 'Use remaining 80C',
        message: 'Use remaining 80C.',
        gapAmount: 50000,
        difficulty: GapDifficulty.easy,
        difficultyLabel: 'Easy',
        deadline: '31 March 2027',
        actions: [],
        colorHex: 'F5C842',
      ),
    ],
    totalGapAmount: 50000,
    estimatedTaxBenefit: 15000,
    gapCount: 1,
    assumptions: [
      TaxAssumption(
        code: 'hra_estimated',
        title: 'HRA estimated',
        detail: 'Actual HRA was not supplied, so ARTH used a salary estimate.',
      ),
    ],
  );
}
