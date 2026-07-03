import '../models/user_profile.dart';
import '../models/tax_result.dart';
import '../models/gap_card.dart';
import '../models/tax_rule_set.dart';

/// Core tax calculation engine.
/// Uses versioned rule assets so filing and planning years are explicit.
class TaxEngine {
  static TaxResult calculate(
    UserProfile profile,
    List<GapCard> gaps, {
    required TaxRuleSet ruleSet,
  }) {
    final assumptions = _assumptions(profile);
    final oldResult = _calculateOldRegime(profile, ruleSet);
    final newResult = _calculateNewRegime(profile, ruleSet);

    final oldTax = oldResult['tax'] as double;
    final newTax = newResult['tax'] as double;
    final oldTaxable = oldResult['taxable'] as double;
    final newTaxable = newResult['taxable'] as double;
    final totalDeductionsOld = oldResult['deductions'] as double;

    final betterRegime =
        oldTax <= newTax ? TaxRegime.oldRegime : TaxRegime.newRegime;
    final regimeSavings = (oldTax - newTax).abs();

    final totalGapAmount = gaps.fold<int>(0, (sum, g) => sum + g.gapAmount);
    final estimatedTaxBenefit = _estimateTaxBenefit(
      profile,
      ruleSet,
      currentTax: betterRegime == TaxRegime.oldRegime ? oldTax : newTax,
      newTax: newTax,
      totalGapAmount: totalGapAmount,
    );

    return TaxResult(
      ruleSetId: ruleSet.id.wireName,
      ruleSetLabel: ruleSet.displayLabel,
      assessmentYear: ruleSet.assessmentYear,
      calculationMode: ruleSet.calculationMode,
      oldRegimeTax: oldTax,
      newRegimeTax: newTax,
      oldRegimeTaxableIncome: oldTaxable,
      newRegimeTaxableIncome: newTaxable,
      totalDeductionsOld: totalDeductionsOld,
      betterRegime: betterRegime,
      regimeSavings: regimeSavings,
      gaps: gaps,
      totalGapAmount: totalGapAmount,
      deductionOpportunity: totalGapAmount,
      estimatedTaxBenefit: estimatedTaxBenefit,
      gapCount: gaps.length,
      assumptions: assumptions,
      trace: TaxComputationTrace(
        oldTaxBeforeCess: oldResult['taxBeforeCess'] as double,
        newTaxBeforeCess: newResult['taxBeforeCess'] as double,
        oldSurcharge: oldResult['surcharge'] as double,
        newSurcharge: newResult['surcharge'] as double,
        oldCess: oldResult['cess'] as double,
        newCess: newResult['cess'] as double,
      ),
    );
  }

  // ─── NEW REGIME ─────────────────────────────────────────────────────────────
  static Map<String, double> _calculateNewRegime(
    UserProfile p,
    TaxRuleSet ruleSet,
  ) {
    double gross = p.annualCTC.toDouble();
    final rule = ruleSet.newRegime;

    // Standard deduction
    double deductions = rule.standardDeduction.toDouble();

    if (p.employerNpsContribution != null) {
      deductions += _employerNpsDeduction(p);
    }

    double taxable = gross - deductions;
    if (taxable < 0) taxable = 0;

    double tax = _applySlabs(taxable, rule.slabs);

    // 87A rebate
    if (taxable <= rule.rebate87ALimit) {
      double rebate =
          tax < rule.rebate87AAmount ? tax : rule.rebate87AAmount.toDouble();
      tax = tax - rebate;
      if (tax < 0) tax = 0;
    }

    // Surcharge
    double surcharge = _surcharge(tax, taxable, isNew: true);

    // Cess 4%
    double cess = (tax + surcharge) * ruleSet.cessRate;

    return {
      'tax': tax + surcharge + cess,
      'taxBeforeCess': tax,
      'surcharge': surcharge,
      'cess': cess,
      'taxable': taxable,
      'deductions': deductions,
    };
  }

  // ─── OLD REGIME ─────────────────────────────────────────────────────────────
  static Map<String, double> _calculateOldRegime(
    UserProfile p,
    TaxRuleSet ruleSet, {
    double extraDeductions = 0,
  }) {
    double gross = p.annualCTC.toDouble();
    final rule = ruleSet.oldRegime;
    double deductions = 0;

    // Standard deduction (old regime)
    deductions += rule.standardDeduction;

    // Professional tax — only applicable for salaried employees (max ₹2,500)
    if (p.employmentType == EmploymentType.salaried) {
      deductions += p.actualProfessionalTax ?? rule.professionalTaxDefault;
    }

    // HRA exemption
    if (p.paysRent && p.hasHRA) {
      deductions += _hraExemption(p).toDouble();
    }

    // 80GG (rent but no HRA)
    if (p.paysRentNoHRA) {
      deductions += _80GG(p);
    }

    // Section 24(b) — home loan interest (self-occupied, max 2L)
    if (p.hasHomeLoanSelfOccupied) {
      double interest = p.homeLoanInterest.toDouble();
      deductions += interest < 200000 ? interest : 200000;
    }

    // 80C (max 1.5L)
    double c80 = p.invested80C.toDouble();
    final c80Cap = ruleSet.deductionCaps['80c'] ?? 150000;
    deductions += c80 < c80Cap ? c80 : c80Cap.toDouble();

    // 80CCD(1B) — extra NPS (max 50k)
    double npsExtra = p.npsExtraContribution.toDouble();
    final npsCap = ruleSet.deductionCaps['80ccd_1b'] ?? 50000;
    deductions += npsExtra < npsCap ? npsExtra : npsCap.toDouble();

    if (p.employerNpsContribution != null) {
      deductions += _employerNpsDeduction(p);
    }

    // 80D
    // The onboarding flow only captures whether cover exists, not the premium
    // actually paid. To avoid overstating old-regime savings, the regime
    // comparison excludes 80D from the tax payable calculation until the app
    // collects rupee amounts for the premium.
    deductions += _calculate80D(p, ruleSet);

    // 80E — education loan interest (no cap, max 8 years)
    if (p.hasEducationLoan && p.educationLoanRepaymentYear <= 8) {
      deductions += p.educationLoanInterest.toDouble();
    }

    // 80G — donations (simplified: 50% of amount, no qualifying limit applied here)
    if (p.hasDonations) {
      final rate = (p.donationDeductionRatePercent ?? 50).clamp(0, 100) / 100;
      deductions += (p.donationAmount * rate).toDouble();
    }

    // 80TTA / 80TTB
    if (p.savingsInterest != null && p.ageBelow60) {
      final cap = ruleSet.deductionCaps['80tta'] ?? 10000;
      final interest = p.savingsInterest!.toDouble();
      deductions += interest < cap ? interest : cap.toDouble();
    }
    if ((p.savingsInterest != null || p.fdInterest != null) && p.ageAbove60) {
      final cap = ruleSet.deductionCaps['80ttb'] ?? 50000;
      final interest = (p.savingsInterest ?? 0) + (p.fdInterest ?? 0);
      deductions += interest < cap ? interest.toDouble() : cap.toDouble();
    }

    deductions += extraDeductions;

    double taxable = gross - deductions;
    if (taxable < 0) taxable = 0;

    // Apply slabs based on age, including the super-senior old-regime slab.
    List<TaxSlab> slabs;
    if (p.ageAbove60) {
      slabs = p.ageAbove80
          ? rule.slabs80Plus ?? rule.slabs
          : rule.slabs60To79 ?? rule.slabs;
    } else {
      slabs = rule.slabs;
    }
    double tax = _applySlabs(taxable, slabs);

    // 87A rebate
    if (taxable <= rule.rebate87ALimit) {
      double rebate =
          tax < rule.rebate87AAmount ? tax : rule.rebate87AAmount.toDouble();
      tax = tax - rebate;
      if (tax < 0) tax = 0;
    }

    // Surcharge
    double surcharge = _surcharge(tax, taxable, isNew: false);

    // Cess 4%
    double cess = (tax + surcharge) * ruleSet.cessRate;

    return {
      'tax': tax + surcharge + cess,
      'taxBeforeCess': tax,
      'surcharge': surcharge,
      'cess': cess,
      'taxable': taxable,
      'deductions': deductions,
    };
  }

  // ─── HRA EXEMPTION ───────────────────────────────────────────────────────────
  static int _hraExemption(UserProfile p) {
    // Min of: actual HRA | 50%/40% of basic | rent - 10% basic
    double basic = p.approximateBasicSalary.toDouble();
    double annualRent = p.monthlyRent * 12.0;

    double actualHRA = p.actualHraReceived?.toDouble() ?? basic * 0.40;

    // HRA % of salary
    double hraPercent = p.isMetroCity ? 0.50 : 0.40;
    double salaryPercent = basic * hraPercent;

    // Rent - 10% basic
    double rentMinus10 = annualRent - (basic * 0.10);
    if (rentMinus10 < 0) rentMinus10 = 0;

    double exemption = [
      actualHRA,
      salaryPercent,
      rentMinus10,
    ].reduce((a, b) => a < b ? a : b);

    return exemption.round();
  }

  // ─── 80GG ─────────────────────────────────────────────────────────────────
  static double _80GG(UserProfile p) {
    double ati = p.annualCTC.toDouble() * 0.85; // approximation
    double annualRent = p.monthlyRent * 12.0;

    double option1 = 60000; // 5000/month
    double option2 = ati * 0.25;
    double option3 = annualRent - (ati * 0.10);
    if (option3 < 0) option3 = 0;

    return [option1, option2, option3].reduce((a, b) => a < b ? a : b);
  }

  // ─── 80D ─────────────────────────────────────────────────────────────────
  static double _calculate80D(UserProfile p, TaxRuleSet ruleSet) {
    double deduction = 0;
    if (p.healthInsuranceSelfPremium != null) {
      final cap = p.ageAbove60
          ? ruleSet.deductionCaps['80d_self_above60'] ?? 50000
          : ruleSet.deductionCaps['80d_self_below60'] ?? 25000;
      deduction += p.healthInsuranceSelfPremium! < cap
          ? p.healthInsuranceSelfPremium!.toDouble()
          : cap.toDouble();
    }
    if (p.healthInsuranceParentsPremium != null) {
      final cap = p.parentsAbove60
          ? ruleSet.deductionCaps['80d_parents_above60'] ?? 50000
          : ruleSet.deductionCaps['80d_parents_below60'] ?? 25000;
      deduction += p.healthInsuranceParentsPremium! < cap
          ? p.healthInsuranceParentsPremium!.toDouble()
          : cap.toDouble();
    }
    return deduction;
  }

  static double _employerNpsDeduction(UserProfile p) {
    final contribution = p.employerNpsContribution ?? 0;
    final cap = p.approximateBasicSalary * 0.10;
    return contribution < cap ? contribution.toDouble() : cap;
  }

  // ─── SURCHARGE ───────────────────────────────────────────────────────────
  static double _surcharge(double tax, double taxable, {required bool isNew}) {
    if (taxable <= 5000000) return 0;
    if (taxable <= 10000000) return tax * 0.10;
    if (taxable <= 20000000) return tax * 0.15;
    if (taxable <= 50000000) return tax * 0.25;
    // Above 5 Cr
    return isNew ? tax * 0.25 : tax * 0.37;
  }

  // ─── SLAB APPLICATION ────────────────────────────────────────────────────
  static double _applySlabs(double income, List<TaxSlab> slabs) {
    double tax = 0;
    for (final slab in slabs) {
      if (income <= slab.from) break;
      double upper = slab.to < income ? slab.to : income;
      tax += (upper - slab.from) * slab.rate;
    }
    return tax;
  }

  // ─── TAX RATE AT INCOME LEVEL (for gap savings display) ──────────────────
  static double marginalRateOldRegime(double income) {
    if (income <= 250000) return 0;
    if (income <= 500000) return 0.05;
    if (income <= 1000000) return 0.20;
    return 0.30;
  }

  static double marginalRateNewRegime(double income) {
    if (income <= 400000) return 0;
    if (income <= 800000) return 0.05;
    if (income <= 1200000) return 0.10;
    if (income <= 1600000) return 0.15;
    if (income <= 2000000) return 0.20;
    if (income <= 2400000) return 0.25;
    return 0.30;
  }

  static int _estimateTaxBenefit(
    UserProfile profile,
    TaxRuleSet ruleSet, {
    required double currentTax,
    required double newTax,
    required int totalGapAmount,
  }) {
    if (totalGapAmount <= 0) return 0;
    final oldWithGap = _calculateOldRegime(
      profile,
      ruleSet,
      extraDeductions: totalGapAmount.toDouble(),
    )['tax'] as double;
    final bestAfterAction = oldWithGap < newTax ? oldWithGap : newTax;
    final benefit = currentTax - bestAfterAction;
    return benefit > 0 ? benefit.round() : 0;
  }

  static List<TaxAssumption> _assumptions(UserProfile p) {
    final assumptions = <TaxAssumption>[];
    if (p.actualBasicSalary == null) {
      assumptions.add(
        const TaxAssumption(
          code: 'basic_salary_estimated',
          title: 'Basic salary estimated',
          detail:
              'Basic salary is assumed at 40% of CTC until Form 16 or salary breakup is added.',
          severity: TaxAssumptionSeverity.caution,
        ),
      );
    }
    if (p.paysRent && p.hasHRA && p.actualHraReceived == null) {
      assumptions.add(
        const TaxAssumption(
          code: 'hra_estimated',
          title: 'HRA estimated',
          detail:
              'Actual HRA received is not collected yet, so HRA exemption uses a standard salary-structure estimate.',
          severity: TaxAssumptionSeverity.caution,
        ),
      );
    }
    if (p.employmentType == EmploymentType.salaried &&
        p.actualProfessionalTax == null) {
      assumptions.add(
        const TaxAssumption(
          code: 'professional_tax_default',
          title: 'Professional tax defaulted',
          detail:
              'Professional tax uses the statutory maximum placeholder until exact payslip data is added.',
        ),
      );
    }
    if ((p.hasHealthInsuranceSelf || p.hasHealthInsuranceParents) &&
        p.healthInsuranceSelfPremium == null &&
        p.healthInsuranceParentsPremium == null) {
      assumptions.add(
        const TaxAssumption(
          code: '80d_not_modeled',
          title: '80D premium not modeled',
          detail:
              'Health insurance yes/no is tracked, but premium amounts are needed before 80D affects tax payable.',
          severity: TaxAssumptionSeverity.caution,
        ),
      );
    }
    if (p.savingsInterest == null && p.fdInterest == null) {
      assumptions.add(
        const TaxAssumption(
          code: 'interest_income_not_modeled',
          title: 'Interest income not modeled',
          detail:
              '80TTA/80TTB appears as readiness guidance unless bank interest amounts are entered.',
        ),
      );
    }
    if (p.hasDonations && p.donationDeductionRatePercent == null) {
      assumptions.add(
        const TaxAssumption(
          code: 'donation_rate_estimated',
          title: 'Donation deduction rate estimated',
          detail:
              'Donation benefit is modeled at 50% until eligible donation category is confirmed.',
        ),
      );
    }
    return assumptions;
  }
}
