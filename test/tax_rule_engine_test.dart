import 'dart:convert';
import 'dart:io';

import 'package:arth/engine/tax_engine.dart';
import 'package:arth/models/gap_card.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/models/form16_tax_prefill.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/tax_rule_set.dart';
import 'package:arth/models/user_profile.dart';
import 'package:arth/providers/tax_year_provider.dart';
import 'package:arth/providers/tax_result_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tax result computes without an authenticated completion flag',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container.read(taxResultProvider.future);

    expect(result.ruleSetLabel, 'FY2026-27 Planning');
    expect(result.newRegimeTax, greaterThanOrEqualTo(0));
  });

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

  // ─── Batch 1: engine correctness ────────────────────────────────────────

  test('A1: standard deduction only for salaried, not self-employed', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    const base = UserProfile(annualCTC: 1500000);

    final salaried = TaxEngine.calculate(
      base.copyWith(employmentType: EmploymentType.salaried),
      const [],
      ruleSet: ruleSet,
    );
    final selfEmployed = TaxEngine.calculate(
      base.copyWith(employmentType: EmploymentType.selfEmployed),
      const [],
      ruleSet: ruleSet,
    );

    // Salaried gets the ₹75k standard deduction; self-employed does not.
    expect(salaried.newRegimeTaxableIncome, 1500000 - 75000);
    expect(selfEmployed.newRegimeTaxableIncome, 1500000);
  });

  test('A2: 80CCD(2) employer NPS capped at 14% of basic in new regime', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    final result = TaxEngine.calculate(
      const UserProfile(
        annualCTC: 2000000,
        employmentType: EmploymentType.salaried,
        actualBasicSalary: 1000000,
        employerNpsContribution: 200000, // above the 14% cap (140000)
      ),
      const [],
      ruleSet: ruleSet,
    );

    // gross 2,000,000 − SD 75,000 − 80CCD(2) capped 140,000 = 1,785,000.
    expect(result.newRegimeTaxableIncome, 1785000);
  });

  test('A3: old-regime 87A has no marginal relief above the limit', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    // Self-employed so taxable == CTC (no standard deduction / PT).
    final result = TaxEngine.calculate(
      const UserProfile(
        annualCTC: 510000,
        employmentType: EmploymentType.selfEmployed,
      ),
      const [],
      ruleSet: ruleSet,
    );

    // Old tax on 510000: 12,500 (250-500k @5%) + 2,000 (500-510k @20%) = 14,500
    // pre-cess; the buggy code capped it to ≈9,600 via wrongful marginal relief.
    expect(result.trace.oldTaxBeforeCess, closeTo(14500, 1));
  });

  test('A4: surcharge marginal relief bounds the jump over ₹50L', () {
    final ruleSet = _loadRuleSet(TaxYearId.fy2026_27);
    UserProfile p(int ctc) => UserProfile(
          annualCTC: ctc,
          employmentType: EmploymentType.selfEmployed,
        );
    double preCessOld(int ctc) {
      final r = TaxEngine.calculate(p(ctc), const [], ruleSet: ruleSet);
      return r.trace.oldTaxBeforeCess + r.trace.oldSurcharge;
    }

    // Marginal relief: (tax+surcharge) increment over the ₹50L threshold must
    // not exceed the ₹1L of extra income. Without relief the 10% surcharge on
    // ~₹13.4L of tax would add ~₹1.34L — far more than ₹1L.
    final increment = preCessOld(5100000) - preCessOld(5000000);
    expect(increment, lessThanOrEqualTo(100001));
  });

  test('A8: metro HRA list expands from 4 (FY25-26) to 8 (FY26-27)', () {
    final filing = _loadRuleSet(TaxYearId.fy2025_26);
    final planning = _loadRuleSet(TaxYearId.fy2026_27);

    expect(filing.isHraMetro('Delhi'), isTrue);
    expect(filing.isHraMetro('Bengaluru'), isFalse);

    expect(planning.isHraMetro('Delhi'), isTrue);
    expect(planning.isHraMetro('bengaluru'), isTrue); // case-insensitive
    expect(planning.isHraMetro('Pune'), isTrue);
    expect(planning.isHraMetro('Hyderabad'), isTrue);
    expect(planning.isHraMetro('Ahmedabad'), isTrue);
    expect(planning.isHraMetro('Jaipur'), isFalse);
  });

  // ─── Batch 2: 80D / 80G depth ───────────────────────────────────────────

  // Self-employed isolates old-regime deductions (no standard deduction / PT),
  // so totalDeductionsOld reflects only the section under test.
  UserProfile selfEmp(UserProfile Function(UserProfile) f) => f(
        const UserProfile(
          annualCTC: 2000000,
          employmentType: EmploymentType.selfEmployed,
        ),
      );

  double deductionsOld(UserProfile p) => TaxEngine.calculate(
        p,
        const [],
        ruleSet: _loadRuleSet(TaxYearId.fy2026_27),
      ).totalDeductionsOld;

  test('80D: self premium capped at ₹25k; preventive adds up to ₹5k', () {
    final premiumOnly = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasHealthInsuranceSelf: true,
            healthInsuranceSelfPremium: 20000,
          )),
    );
    final withPreventive = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasHealthInsuranceSelf: true,
            healthInsuranceSelfPremium: 20000,
            preventiveHealthCheckup: 8000, // clamped to 5,000
          )),
    );
    expect(premiumOnly, 20000);
    expect(withPreventive, 25000); // 20k + 5k preventive, within the ₹25k cap
  });

  test('80D: senior parents premium capped at ₹50k', () {
    final d = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasHealthInsuranceParents: true,
            parentsAbove60: true,
            healthInsuranceParentsPremium: 70000,
          )),
    );
    expect(d, 50000);
  });

  test('80G: 100%-no-limit category deducts the full amount', () {
    final d = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasDonations: true,
            donationAmount: 100000,
            donationCategory: DonationCategory.hundredNoLimit,
          )),
    );
    expect(d, 100000);
  });

  test('80G: 50%-with-limit category applies rate then 10%-GTI cap', () {
    // Adjusted GTI ≈ 20,00,000 → 10% cap = 2,00,000. Donation 1,00,000 < cap,
    // so eligible = 1,00,000 × 50% = 50,000.
    final d = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasDonations: true,
            donationAmount: 100000,
            donationCategory: DonationCategory.fiftyWithLimit,
          )),
    );
    expect(d, 50000);
  });

  test('80G: donation above the 10%-GTI qualifying limit is capped', () {
    // 10% of ~20L = 2,00,000 cap; donate 5,00,000 at 50% → min(5L,2L)×0.5 = 1L.
    final d = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasDonations: true,
            donationAmount: 500000,
            donationCategory: DonationCategory.fiftyWithLimit,
          )),
    );
    expect(d, 100000);
  });

  test('80G: cash donation over ₹2,000 is ineligible', () {
    final d = deductionsOld(
      selfEmp((p) => p.copyWith(
            hasDonations: true,
            donationAmount: 100000,
            donationInCash: true,
            donationCategory: DonationCategory.hundredNoLimit,
          )),
    );
    expect(d, 0);
  });

  test('new fields survive a profile JSON round-trip', () {
    const p = UserProfile(
      hasDonations: true,
      donationAmount: 50000,
      donationCategory: DonationCategory.fiftyWithLimit,
      donationInCash: true,
      healthInsuranceSelfPremium: 22000,
      preventiveHealthCheckup: 5000,
      regimePreference: RegimePreference.oldRegime,
    );
    final restored = UserProfile.fromJson(p.toJson());
    expect(restored.donationCategory, DonationCategory.fiftyWithLimit);
    expect(restored.donationInCash, isTrue);
    expect(restored.preventiveHealthCheckup, 5000);
    expect(restored.healthInsuranceSelfPremium, 22000);
    expect(restored.regimePreference, RegimePreference.oldRegime);
  });

  // ─── Batch 4: Form 16 prefill ───────────────────────────────────────────

  TaxDocument form16Doc(Map<String, dynamic> confirmed) =>
      TaxDocument.fromJson({
        'id': 'f16-1',
        'fy': 'FY2026-27',
        'documentType': 'form16',
        'originalFilename': 'form16.pdf',
        'mimeType': 'application/pdf',
        'byteSize': 2048,
        'parseStatus': 'parsed',
        'confirmedFields': confirmed,
      });

  test('Form 16 prefill maps gross salary + employer onto the profile', () {
    final prefill = form16TaxPrefillFromDocuments([
      form16Doc({
        'grossSalary': 1800000,
        'employerName': 'Acme Corp',
        'chapterViaDeductions': 150000,
        'taxDeductedAtSource': 90000,
        'taxableIncome': 1650000,
      }),
    ]);
    expect(prefill, isNotNull);
    expect(prefill!.taxDeductedAtSource, 90000);
    final p = prefill.applyTo(const UserProfile(annualCTC: 1000000));
    expect(p.annualCTC, 1800000);
    expect(p.employerName, 'Acme Corp');
    expect(p.employmentType, EmploymentType.salaried);
  });

  test('Form 16 prefill ignores payslip documents and empty confirmations', () {
    final payslipLike = TaxDocument.fromJson({
      'id': 'p-1',
      'fy': 'FY2026-27',
      'documentType': 'payslip',
      'originalFilename': 'slip.pdf',
      'mimeType': 'application/pdf',
      'byteSize': 1024,
      'parseStatus': 'parsed',
      'confirmedFields': {
        'earnings': [],
        'deductions': [],
        'netSalary': 90000,
      },
    });
    expect(form16TaxPrefillFromDocuments([payslipLike]), isNull);
    expect(form16TaxPrefillFromDocuments([form16Doc(const {})]), isNull);
  });
}

TaxRuleSet _loadRuleSet(TaxYearId id) {
  final raw = File(id.assetPath).readAsStringSync();
  return TaxRuleSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
