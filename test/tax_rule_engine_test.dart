import 'dart:convert';
import 'dart:io';

import 'package:arth/engine/tax_engine.dart';
import 'package:arth/models/gap_card.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/tax_rule_set.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/tax_year_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic defaults to latest active planning year', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(activeTaxYearProvider), TaxYearId.fy2026_27);
  });

  test('bundled tax rule assets expose filing and planning context', () {
    final filing = _loadRuleSet(TaxYearId.fy2025_26);
    final planning = _loadRuleSet(TaxYearId.fy2026_27);

    expect(filing.displayLabel, 'FY2025-26 Filing');
    expect(filing.assessmentYear, 'AY 2026-27');
    expect(filing.calculationMode, CalculationMode.filing);
    expect(filing.newRegime.standardDeduction, 75000);
    expect(filing.newRegime.rebate87ALimit, 1200000);

    expect(planning.displayLabel, 'FY2026-27 Planning');
    expect(planning.assessmentYear, 'AY 2027-28');
    expect(planning.calculationMode, CalculationMode.planning);
    expect(planning.sourceUrls, isNotEmpty);
  });

  test('new regime salary rebate boundary is explicit for filing mode', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2025_26);

    final result = TaxEngine.calculate(
      const UserProfile(annualCTC: 1275000),
      const [],
      ruleSet: ruleSet,
    );

    expect(result.ruleSetLabel, 'FY2025-26 Filing');
    expect(result.assessmentYear, 'AY 2026-27');
    expect(result.newRegimeTaxableIncome, 1200000);
    expect(result.newRegimeTax, 0);
  });

  test('super-senior old-regime slabs are distinct when income crosses 5L', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2025_26);
    const base = UserProfile(
      annualCTC: 650000,
      employmentType: EmploymentType.salaried,
    );

    final senior = TaxEngine.calculate(
      base.copyWith(ageGroup: AgeGroup.above60),
      const [],
      ruleSet: ruleSet,
    );
    final superSenior = TaxEngine.calculate(
      base.copyWith(ageGroup: AgeGroup.above80),
      const [],
      ruleSet: ruleSet,
    );

    expect(superSenior.oldRegimeTax, lessThan(senior.oldRegimeTax));
  });

  test('deduction opportunity and estimated tax benefit stay separated', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2025_26);
    const gaps = [
      GapCard(
        id: 'gap_80c',
        section: '80C',
        title: '80C headroom',
        shortDesc: 'Unused 80C room',
        message: 'Invest eligible amount before the deadline.',
        gapAmount: 100000,
        difficulty: GapDifficulty.medium,
        difficultyLabel: 'Medium',
        deadline: '31 Mar 2026',
        actions: [],
        colorHex: 'F5C842',
      ),
    ];

    final result = TaxEngine.calculate(
      const UserProfile(annualCTC: 1800000),
      gaps,
      ruleSet: ruleSet,
    );

    expect(result.deductionOpportunity, 100000);
    expect(result.estimatedTaxBenefit, greaterThanOrEqualTo(0));
    expect(result.estimatedTaxBenefit, lessThanOrEqualTo(100000));
    expect(result.assumptions.map((item) => item.code),
        contains('basic_salary_estimated'));
  });

  test('already-modeled guidance gaps do not inflate estimated tax benefit',
      () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    const gaps = [
      GapCard(
        id: 'T08_section24b_home_loan',
        section: 'Section 24(b)',
        title: 'Home loan interest',
        shortDesc: 'Already entered',
        message: 'Use your certificate while filing.',
        gapAmount: 200000,
        difficulty: GapDifficulty.easy,
        difficultyLabel: 'Easy',
        deadline: '31 July 2027',
        actions: [],
        colorHex: 'F5C842',
      ),
      GapCard(
        id: 'T09_80TTA',
        section: '80TTA',
        title: 'Savings interest',
        shortDesc: 'Already modeled',
        message: 'Review your bank interest.',
        gapAmount: 10000,
        difficulty: GapDifficulty.easy,
        difficultyLabel: 'Easy',
        deadline: '31 July 2027',
        actions: [],
        colorHex: '26A69A',
      ),
    ];

    final result = TaxEngine.calculate(
      const UserProfile(
        annualCTC: 1800000,
        hasHomeLoan: true,
        propertyType: PropertyType.selfOccupied,
        homeLoanInterest: 200000,
        savingsInterest: 10000,
      ),
      gaps,
      ruleSet: ruleSet,
    );

    expect(result.deductionOpportunity, 210000);
    expect(result.estimatedTaxBenefit, 0);
  });

  test('tax result confidence and document parse status survive json roundtrip',
      () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    final result = TaxEngine.calculate(
      const UserProfile(
        annualCTC: 1800000,
        actualBasicSalary: 720000,
        actualProfessionalTax: 2400,
        savingsInterest: 4000,
      ),
      const [],
      ruleSet: ruleSet,
    );
    final restored = TaxResult.fromJson(result.toJson());

    expect(restored.confidenceScore, result.confidenceScore);
    expect(restored.confidenceLabel, result.confidenceLabel);
    expect(restored.confidenceScore, greaterThan(70));

    final document = TaxDocument.fromJson({
      'id': 'doc-1',
      'fy': 'FY2026-27',
      'documentType': 'form16',
      'originalFilename': 'form16.pdf',
      'mimeType': 'application/pdf',
      'byteSize': 2048,
      'parseStatus': 'needs_confirmation',
      'parseSummary': {
        'extractedFields': {
          'employerTan': 'ABCD12345E',
          'grossSalary': 1800000,
        },
      },
    });

    expect(document.needsConfirmation, isTrue);
    expect(document.parseStatusLabel, 'Review needed');
    expect(document.extractedFields['grossSalary'], 1800000);
  });
}

TaxRuleSet _loadRuleSet(TaxYearId id) {
  final raw = File(id.assetPath).readAsStringSync();
  return TaxRuleSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
