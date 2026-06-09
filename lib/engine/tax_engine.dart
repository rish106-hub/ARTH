import '../models/user_profile.dart';
import '../models/tax_result.dart';
import '../models/gap_card.dart';

/// Core tax calculation engine.
/// Based on Finance Act 2026 / FY 2026-27 / AY 2027-28
class TaxEngine {
  static const double _cessRate = 0.04;

  static TaxResult calculate(UserProfile profile, List<GapCard> gaps) {
    final oldResult = _calculateOldRegime(profile);
    final newResult = _calculateNewRegime(profile);

    final oldTax = oldResult['tax'] as double;
    final newTax = newResult['tax'] as double;
    final oldTaxable = oldResult['taxable'] as double;
    final newTaxable = newResult['taxable'] as double;
    final totalDeductionsOld = oldResult['deductions'] as double;

    final betterRegime =
        oldTax <= newTax ? TaxRegime.oldRegime : TaxRegime.newRegime;
    final regimeSavings = (oldTax - newTax).abs();

    final totalGapAmount = gaps.fold<int>(0, (sum, g) => sum + g.gapAmount);

    return TaxResult(
      oldRegimeTax: oldTax,
      newRegimeTax: newTax,
      oldRegimeTaxableIncome: oldTaxable,
      newRegimeTaxableIncome: newTaxable,
      totalDeductionsOld: totalDeductionsOld,
      betterRegime: betterRegime,
      regimeSavings: regimeSavings,
      gaps: gaps,
      totalGapAmount: totalGapAmount,
      gapCount: gaps.length,
    );
  }

  // ─── NEW REGIME ─────────────────────────────────────────────────────────────
  static Map<String, double> _calculateNewRegime(UserProfile p) {
    double gross = p.annualCTC.toDouble();

    // Standard deduction
    double stdDeduction = 75000;
    double taxable = gross - stdDeduction;
    if (taxable < 0) taxable = 0;

    double tax = _applySlabs(taxable, _newRegimeSlabs);

    // 87A rebate: if net taxable ≤ 12L, rebate up to ₹60,000
    if (taxable <= 1200000) {
      double rebate = tax < 60000 ? tax : 60000;
      tax = tax - rebate;
      if (tax < 0) tax = 0;
    }

    // Surcharge
    double surcharge = _surcharge(tax, taxable, isNew: true);

    // Cess 4%
    double cess = (tax + surcharge) * _cessRate;

    return {
      'tax': tax + surcharge + cess,
      'taxable': taxable,
      'deductions': stdDeduction,
    };
  }

  // ─── OLD REGIME ─────────────────────────────────────────────────────────────
  static Map<String, double> _calculateOldRegime(UserProfile p) {
    double gross = p.annualCTC.toDouble();
    double deductions = 0;

    // Standard deduction (old regime)
    deductions += 50000;

    // Professional tax — only applicable for salaried employees (max ₹2,500)
    if (p.employmentType == EmploymentType.salaried) {
      deductions += 2500;
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
    deductions += c80 < 150000 ? c80 : 150000;

    // 80CCD(1B) — extra NPS (max 50k)
    double npsExtra = p.npsExtraContribution.toDouble();
    deductions += npsExtra < 50000 ? npsExtra : 50000;

    // 80D
    // The onboarding flow only captures whether cover exists, not the premium
    // actually paid. To avoid overstating old-regime savings, the regime
    // comparison excludes 80D from the tax payable calculation until the app
    // collects rupee amounts for the premium.
    deductions += _calculate80D(p);

    // 80E — education loan interest (no cap, max 8 years)
    if (p.hasEducationLoan && p.educationLoanRepaymentYear <= 8) {
      deductions += p.educationLoanInterest.toDouble();
    }

    // 80G — donations (simplified: 50% of amount, no qualifying limit applied here)
    if (p.hasDonations) {
      deductions += (p.donationAmount * 0.5).toDouble();
    }

    // 80TTA / 80TTB
    // Savings / FD interest amounts are not collected in onboarding, so
    // auto-claiming the full deduction would make the old-regime comparison
    // inaccurate. Keep these as opportunities in the gap flow, not as assumed
    // reductions in tax payable.

    double taxable = gross - deductions;
    if (taxable < 0) taxable = 0;

    // Apply slabs based on age
    // Note: App bundles 60-79 and 80+ into AgeGroup.above60.
    // Super-senior (80+) slabs are not separately distinguished since
    // users can't specify sub-categories within "Above 60".
    List<_Slab> slabs;
    if (p.ageAbove60) {
      slabs = _oldRegimeSlabs60to79;
    } else {
      slabs = _oldRegimeSlabsBelow60;
    }
    double tax = _applySlabs(taxable, slabs);

    // 87A rebate: if net taxable ≤ 5L, rebate up to ₹12,500
    if (taxable <= 500000) {
      double rebate = tax < 12500 ? tax : 12500;
      tax = tax - rebate;
      if (tax < 0) tax = 0;
    }

    // Surcharge
    double surcharge = _surcharge(tax, taxable, isNew: false);

    // Cess 4%
    double cess = (tax + surcharge) * _cessRate;

    return {
      'tax': tax + surcharge + cess,
      'taxable': taxable,
      'deductions': deductions,
    };
  }

  // ─── HRA EXEMPTION ───────────────────────────────────────────────────────────
  static int _hraExemption(UserProfile p) {
    // Min of: actual HRA | 50%/40% of basic | rent - 10% basic
    double basic = p.approximateBasicSalary.toDouble();
    double annualRent = p.monthlyRent * 12.0;

    // Assume HRA = 40% of basic (common structure)
    double actualHRA = basic * 0.40;

    // HRA % of salary
    double hraPercent = p.isMetroCity ? 0.50 : 0.40;
    double salaryPercent = basic * hraPercent;

    // Rent - 10% basic
    double rentMinus10 = annualRent - (basic * 0.10);
    if (rentMinus10 < 0) rentMinus10 = 0;

    double exemption =
        [actualHRA, salaryPercent, rentMinus10].reduce((a, b) => a < b ? a : b);

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
  static double _calculate80D(UserProfile p) {
    return 0;
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
  static double _applySlabs(double income, List<_Slab> slabs) {
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

  // ─── SLAB DATA ───────────────────────────────────────────────────────────
  static const List<_Slab> _newRegimeSlabs = [
    _Slab(0, 400000, 0.00),
    _Slab(400000, 800000, 0.05),
    _Slab(800000, 1200000, 0.10),
    _Slab(1200000, 1600000, 0.15),
    _Slab(1600000, 2000000, 0.20),
    _Slab(2000000, 2400000, 0.25),
    _Slab(2400000, 999999999, 0.30),
  ];

  static const List<_Slab> _oldRegimeSlabsBelow60 = [
    _Slab(0, 250000, 0.00),
    _Slab(250000, 500000, 0.05),
    _Slab(500000, 1000000, 0.20),
    _Slab(1000000, 999999999, 0.30),
  ];

  static const List<_Slab> _oldRegimeSlabs60to79 = [
    _Slab(0, 300000, 0.00),
    _Slab(300000, 500000, 0.05),
    _Slab(500000, 1000000, 0.20),
    _Slab(1000000, 999999999, 0.30),
  ];
}

class _Slab {
  final double from;
  final double to;
  final double rate;
  const _Slab(this.from, this.to, this.rate);
}
