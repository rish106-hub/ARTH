import 'tax_document.dart';
import 'user_profile.dart';

class PayslipTaxPrefill {
  const PayslipTaxPrefill({
    required this.documentId,
    required this.documentName,
    required this.payPeriod,
    required this.annualGrossSalary,
    required this.annualBasicSalary,
    required this.annualHraReceived,
    required this.annualProfessionalTax,
    required this.employerName,
  });

  final String documentId;
  final String documentName;
  final String payPeriod;
  final int? annualGrossSalary;
  final int? annualBasicSalary;
  final int? annualHraReceived;
  final int? annualProfessionalTax;
  final String? employerName;

  bool get hasSalaryValues =>
      annualGrossSalary != null ||
      annualBasicSalary != null ||
      annualHraReceived != null ||
      annualProfessionalTax != null;

  UserProfile applyTo(UserProfile profile) {
    return profile.copyWith(
      annualCTC: annualGrossSalary ?? profile.annualCTC,
      employmentType: EmploymentType.salaried,
      employerName: employerName ?? profile.employerName,
      hasHRA:
          annualHraReceived == null ? profile.hasHRA : annualHraReceived! > 0,
      actualBasicSalary: annualBasicSalary ?? profile.actualBasicSalary,
      actualHraReceived: annualHraReceived ?? profile.actualHraReceived,
      actualProfessionalTax:
          annualProfessionalTax ?? profile.actualProfessionalTax,
    );
  }
}

PayslipTaxPrefill? payslipTaxPrefillFromDocuments(
  List<TaxDocument> documents,
) {
  final confirmed = documents
      .where(
        (document) =>
            document.active &&
            document.isPayslip &&
            document.parsed &&
            document.confirmedFields.isNotEmpty,
      )
      .toList()
    ..sort((a, b) => _dateFor(b).compareTo(_dateFor(a)));
  if (confirmed.isEmpty) return null;

  final document = confirmed.first;
  final fields = document.confirmedFields;
  final earnings = _rows(fields['earnings']);
  final deductions = _rows(fields['deductions']);
  final gross = _amount(fields['grossEarnings']) ?? _sum(earnings);
  final basic = _sumClassified(earnings, 'basic_pay');
  final hra = _sumClassified(earnings, 'hra');
  final professionalTax = _sumClassified(deductions, 'professional_tax');

  final prefill = PayslipTaxPrefill(
    documentId: document.id,
    documentName: document.displayName,
    payPeriod: _text(fields['payPeriod']) ?? 'latest confirmed month',
    annualGrossSalary: _annualize(gross),
    annualBasicSalary: _annualize(basic),
    annualHraReceived: _annualize(hra),
    annualProfessionalTax: _annualize(professionalTax),
    employerName: _text(fields['employerName']),
  );
  return prefill.hasSalaryValues ? prefill : null;
}

DateTime _dateFor(TaxDocument document) =>
    document.reviewedAt ?? document.createdAt ?? DateTime(1970);

List<Map<String, dynamic>> _rows(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

int _sum(List<Map<String, dynamic>> rows) => rows.fold<int>(
      0,
      (sum, row) => sum + (_amount(row['amount']) ?? 0),
    );

int? _sumClassified(List<Map<String, dynamic>> rows, String classification) {
  final matched = rows.where((row) {
    final label = row['label']?.toString().toLowerCase() ?? '';
    final rowClassification = row['classification']?.toString();
    return rowClassification == classification ||
        (classification == 'basic_pay' && label.contains('basic')) ||
        (classification == 'hra' &&
            (label == 'hra' || label.contains('house rent'))) ||
        (classification == 'professional_tax' &&
            label.contains('professional tax'));
  }).toList(growable: false);
  if (matched.isEmpty) return null;
  return _sum(matched);
}

int? _annualize(int? monthlyValue) =>
    monthlyValue == null || monthlyValue <= 0 ? null : monthlyValue * 12;

int? _amount(Object? value) => value is num ? value.round() : null;

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
