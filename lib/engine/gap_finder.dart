import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../models/gap_card.dart';

/// Runs all 12 decision-tree triggers against the user profile.
/// Returns only the gaps that are triggered (non-zero amount).
class GapFinder {
  static List<GapCard> findGaps(UserProfile p, List<dynamic> triggers) {
    final List<GapCard> result = [];

    for (final trigger in triggers) {
      final t = trigger as Map<String, dynamic>;
      final id = t['id'] as String;
      final int? computedGap = _computeGap(id, t, p);

      if (computedGap != null && computedGap > 0) {
        result.add(GapCard.fromJson(t, computedGap));
      }
    }

    // Sort by gap amount descending (largest gap first)
    result.sort((a, b) => b.gapAmount.compareTo(a.gapAmount));
    return result;
  }

  static int? _computeGap(String id, Map<String, dynamic> t, UserProfile p) {
    switch (id) {
      case 'T01_80C_gap':
        if (p.invested80C < 150000) return 150000 - p.invested80C;
        return null;

      case 'T02_80CCD1B_nps':
        if (p.npsExtraContribution == 0) return 50000;
        if (p.npsExtraContribution < 50000) return 50000 - p.npsExtraContribution;
        return null;

      case 'T03_80D_self':
        if (!p.hasHealthInsuranceSelf) return p.ageAbove60 ? 50000 : 25000;
        return null;

      case 'T04_80D_parents_below60':
        if (!p.hasHealthInsuranceParents && !p.parentsAbove60) return 25000;
        return null;

      case 'T05_80D_parents_above60':
        if (!p.hasHealthInsuranceParents && p.parentsAbove60) return 50000;
        return null;

      case 'T06_80GG_rent':
        if (p.paysRentNoHRA) {
          // Min of: 60000, 25% ATI, rent - 10% ATI
          double ati = p.annualCTC * 0.85;
          double annualRent = p.monthlyRent * 12.0;
          double opt1 = 60000;
          double opt2 = ati * 0.25;
          double opt3 = annualRent - (ati * 0.10);
          if (opt3 < 0) opt3 = 0;
          double gap = [opt1, opt2, opt3].reduce((a, b) => a < b ? a : b);
          return gap.round();
        }
        return null;

      case 'T07_80E_education_loan':
        if (p.hasEducationLoan && p.educationLoanRepaymentYear <= 8) {
          // If user entered their actual interest, use it. Otherwise show a
          // conservative prompt of ₹25,000 (typical annual education loan interest)
          // to remind them to check — the actual saving depends on their interest.
          return p.educationLoanInterest > 0 ? p.educationLoanInterest : 25000;
        }
        return null;

      case 'T08_section24b_home_loan':
        if (p.hasHomeLoanSelfOccupied) {
          int interest = p.homeLoanInterest;
          return interest > 200000 ? 200000 : interest;
        }
        return null;

      case 'T09_80TTA':
        // 80TTA: Deduction up to ₹10,000 on savings account interest (below 60).
        // Shown as a potential gap — many users overlook claiming this.
        // Shown as a low-value informational gap (₹5,000 conservative estimate).
        if (p.ageBelow60) return 5000;
        return null;

      case 'T10_80TTB_senior':
        // 80TTB: Deduction up to ₹50,000 on interest income (FDs + savings) for 60+.
        // Shown as a potential gap — conservative estimate at ₹25,000.
        if (p.ageAbove60) return 25000;
        return null;

      case 'T11_regime_switch':
        // Handled separately via regime comparison
        return null;

      case 'T12_80CCD2_employer_nps':
        // Section 80CCD(2) is an EMPLOYER contribution to NPS — the employee
        // cannot claim this independently. It is the employer's CTC routing
        // decision. We surface this as a notification gap (₹1) so the GapCard
        // still appears as an action item ("Ask HR about NPS routing"), but we
        // do NOT inflate the employee's gap with an amount they cannot fill.
        // The UI card should be marked as 'ask your HR' not 'you can save X'.
        return 1;

      default:
        return null;
    }
  }

  // ─── LOAD TRIGGERS FROM ASSET JSON ───────────────────────────────────────
  static Future<List<dynamic>> loadTriggers() async {
    final jsonStr = await rootBundle.loadString('assets/tax_data.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return (data['decision_tree_triggers'] as List<dynamic>);
  }
}
