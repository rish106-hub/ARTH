import '../../../engine/tax_engine.dart';
import '../../../models/tax_result.dart';
import '../../../models/tax_rule_set.dart';
import '../../../models/user_profile.dart';
import '../models/offer_comparison_models.dart';

/// Estimates monthly take-home for each offer, on one deliberately bare set of
/// assumptions.
///
/// This lives in the app because the tax engine does. The backend decomposes the
/// promise and stops there rather than growing a second copy of slab logic that
/// would have to be kept in step with this one.
///
/// The assumptions are stated, not hidden. Every offer is taxed as a full year of
/// salary with no deductions claimed and no rent, and the cheaper of the two
/// regimes is used. That is not a forecast of anyone's actual tax — it is the
/// only comparison that is fair between two offers, because the deductions a
/// candidate claims are the same whichever job they take, so including them would
/// move both numbers without changing which is larger.
class OfferTakeHomeEngine {
  const OfferTakeHomeEngine._();

  /// The label and the assumptions the UI must show beside any figure this
  /// engine produces. They live here so the caveat cannot drift away from the
  /// calculation it describes.
  ///
  /// Kept as separate short lines rather than one paragraph: the explanation is
  /// longer than a screen should render unprompted, so the caller joins these
  /// behind a disclosure the reader chooses to open.
  static const assumptionLabel = 'How this is estimated';

  static const assumptionLines = [
    'A full year of salary, with no deductions claimed.',
    'Whichever tax regime works out cheaper.',
    'Your deductions apply to either job, so they move both figures.',
  ];

  /// Estimated monthly take-home from guaranteed pay alone, keyed by document id.
  ///
  /// At-risk pay is excluded on purpose: this answers what lands every month
  /// whether or not a bonus pays out. Offers with no comparable guaranteed figure
  /// are absent from the map rather than present as zero.
  static Map<String, int> monthlyTakeHomeByOffer(
    OfferComparison comparison, {
    required TaxRuleSet ruleSet,
  }) {
    final result = <String, int>{};
    for (final offer in comparison.offers) {
      final guaranteed = offer.guaranteedAnnualPay;
      // Only rupee offers: the tax engine models Indian income tax, and running
      // a dollar salary through it would produce a confident wrong number.
      if (guaranteed == null || guaranteed <= 0 || !_isRupees(offer.currency)) {
        continue;
      }
      result[offer.documentId] = _monthlyTakeHome(guaranteed, ruleSet);
    }
    return result;
  }

  static bool _isRupees(String currency) {
    final normalized = currency.trim().toUpperCase();
    return normalized == 'INR' || normalized == '₹';
  }

  static int _monthlyTakeHome(int annualSalary, TaxRuleSet ruleSet) {
    final profile = UserProfile(annualCTC: annualSalary);
    final tax = TaxEngine.calculate(profile, const [], ruleSet: ruleSet);
    final payable = tax.betterRegime == TaxRegime.oldRegime
        ? tax.oldRegimeTax
        : tax.newRegimeTax;
    final annualNet = annualSalary - payable.round();
    return (annualNet / 12).round();
  }
}
