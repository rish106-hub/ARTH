import 'tax_document.dart';
import 'user_profile.dart';

/// Prefill derived from a confirmed Form 16 — the employer's authoritative
/// annual statement. It carries gross salary, the aggregate Chapter VI-A
/// deductions, TDS and taxable income.
///
/// Note: Form 16 reports Chapter VI-A only as an aggregate, so it cannot be
/// decomposed back into individual sections (80C vs 80D vs …). We therefore
/// apply the parts that map cleanly — income and employer — and expose the
/// authoritative totals for display / reconciliation without faking a
/// per-section breakdown that would risk double-counting against the flow.
class Form16TaxPrefill {
  const Form16TaxPrefill({
    required this.documentId,
    required this.documentName,
    required this.annualGrossSalary,
    required this.chapterViaDeductions,
    required this.taxDeductedAtSource,
    required this.taxableIncome,
    required this.employerName,
    required this.financialYear,
  });

  final String documentId;
  final String documentName;
  final int? annualGrossSalary;
  final int? chapterViaDeductions;
  final int? taxDeductedAtSource;
  final int? taxableIncome;
  final String? employerName;
  final String? financialYear;

  bool get hasValues =>
      annualGrossSalary != null ||
      (employerName != null && employerName!.isNotEmpty);

  UserProfile applyTo(UserProfile profile) {
    return profile.copyWith(
      employmentType: EmploymentType.salaried,
      employerName: (employerName != null && employerName!.isNotEmpty)
          ? employerName
          : profile.employerName,
      annualCTC: (annualGrossSalary != null && annualGrossSalary! > 0)
          ? annualGrossSalary!
          : profile.annualCTC,
    );
  }
}

Form16TaxPrefill? form16TaxPrefillFromDocuments(List<TaxDocument> documents) {
  final confirmed = documents
      .where(
        (document) =>
            document.active &&
            document.documentType == 'form16' &&
            !document.isPayslip &&
            document.parsed &&
            document.confirmedFields.isNotEmpty,
      )
      .toList()
    ..sort((a, b) => _dateFor(b).compareTo(_dateFor(a)));
  if (confirmed.isEmpty) return null;

  final fields = confirmed.first.confirmedFields;
  final prefill = Form16TaxPrefill(
    documentId: confirmed.first.id,
    documentName: confirmed.first.displayName,
    annualGrossSalary: _amount(fields['grossSalary']),
    chapterViaDeductions: _amount(fields['chapterViaDeductions']),
    taxDeductedAtSource: _amount(fields['taxDeductedAtSource']),
    taxableIncome: _amount(fields['taxableIncome']),
    employerName: _text(fields['employerName']),
    financialYear: _text(fields['financialYear']),
  );
  return prefill.hasValues ? prefill : null;
}

DateTime _dateFor(TaxDocument document) =>
    document.reviewedAt ?? document.createdAt ?? DateTime(1970);

int? _amount(Object? value) => value is num ? value.round() : null;

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
