import 'tax_document.dart';
import 'user_profile.dart';

/// The proof document types whose confirmed fields carry a structured amount
/// the diagnostic can pre-fill. Mirrors `PROOF_DOCUMENT_TYPES` in the backend
/// `documentParser.ts`.
const _proofTypes = {
  'rentReceipts',
  'investment80c',
  'healthInsurance80d',
  'homeLoanCertificate',
  'educationLoanInterest',
  'donationReceipts',
};

/// Amounts read from confirmed proof documents (rent receipt, 80C/80D proofs,
/// home-loan / education-loan certificates, donation receipts). Applied as a
/// gap-filler: a value is written only when the matching profile field is still
/// at its default, so it never overrides a payslip, Form 16, or a value the
/// user typed themselves.
class ProofPrefill {
  const ProofPrefill(this.values);

  /// Merged numeric fields across confirmed proof docs (backend key → amount).
  final Map<String, int> values;

  bool get isNotEmpty => values.isNotEmpty;

  int? _v(String key) {
    final v = values[key];
    return (v != null && v > 0) ? v : null;
  }

  UserProfile applyTo(UserProfile p) {
    final rent = _v('monthlyRent');
    final premium = _v('healthInsuranceSelfPremium');
    final homeInterest = _v('homeLoanInterest');
    final eduInterest = _v('educationLoanInterest');
    final donation = _v('donationAmount');
    final invested = _v('invested80C');

    return p.copyWith(
      monthlyRent: (p.monthlyRent == 0 && rent != null) ? rent : p.monthlyRent,
      paysRent: rent != null ? true : p.paysRent,
      healthInsuranceSelfPremium:
          (p.healthInsuranceSelfPremium == null && premium != null)
              ? premium
              : p.healthInsuranceSelfPremium,
      hasHealthInsuranceSelf: premium != null ? true : p.hasHealthInsuranceSelf,
      homeLoanInterest: (p.homeLoanInterest == 0 && homeInterest != null)
          ? homeInterest
          : p.homeLoanInterest,
      hasHomeLoan: homeInterest != null ? true : p.hasHomeLoan,
      educationLoanInterest:
          (p.educationLoanInterest == 0 && eduInterest != null)
              ? eduInterest
              : p.educationLoanInterest,
      hasEducationLoan: eduInterest != null ? true : p.hasEducationLoan,
      donationAmount: (p.donationAmount == 0 && donation != null)
          ? donation
          : p.donationAmount,
      hasDonations: donation != null ? true : p.hasDonations,
      invested80C:
          (p.invested80C == 0 && invested != null) ? invested : p.invested80C,
    );
  }
}

ProofPrefill? proofPrefillFromDocuments(List<TaxDocument> documents) {
  final confirmed = documents
      .where((d) =>
          d.active &&
          _proofTypes.contains(d.documentType) &&
          d.parsed &&
          d.confirmedFields.isNotEmpty)
      .toList()
    ..sort((a, b) => _dateFor(a).compareTo(_dateFor(b))); // oldest first

  final merged = <String, int>{};
  for (final doc in confirmed) {
    doc.confirmedFields.forEach((key, value) {
      if (value is num && value > 0) merged[key] = value.round(); // latest wins
    });
  }
  return merged.isEmpty ? null : ProofPrefill(merged);
}

DateTime _dateFor(TaxDocument document) =>
    document.reviewedAt ?? document.createdAt ?? DateTime(1970);
