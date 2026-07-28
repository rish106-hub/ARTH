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
    required this.annualEligible80C,
    required this.annualEmployeeNps,
    required this.annualHealthInsurance,
    required this.employerName,
  });

  final String documentId;
  final String documentName;
  final String payPeriod;
  final int? annualGrossSalary;
  final int? annualBasicSalary;
  final int? annualHraReceived;
  final int? annualProfessionalTax;
  final int? annualEligible80C;
  final int? annualEmployeeNps;
  final int? annualHealthInsurance;
  final String? employerName;

  bool get hasSalaryValues =>
      annualGrossSalary != null ||
      annualBasicSalary != null ||
      annualHraReceived != null ||
      annualProfessionalTax != null ||
      annualEligible80C != null ||
      annualEmployeeNps != null ||
      annualHealthInsurance != null;

  UserProfile applyTo(UserProfile profile) {
    return profile.copyWith(
      employmentType: EmploymentType.salaried,
      employerName: employerName ?? profile.employerName,
      hasHRA:
          annualHraReceived == null ? profile.hasHRA : annualHraReceived! > 0,
      actualBasicSalary: annualBasicSalary ?? profile.actualBasicSalary,
      actualHraReceived: annualHraReceived ?? profile.actualHraReceived,
      actualProfessionalTax:
          annualProfessionalTax ?? profile.actualProfessionalTax,
      invested80C: _larger(profile.invested80C, annualEligible80C),
      hasNPS: annualEmployeeNps == null
          ? profile.hasNPS
          : _larger(profile.npsExtraContribution, annualEmployeeNps) > 0,
      npsExtraContribution: _larger(
        profile.npsExtraContribution,
        annualEmployeeNps,
      ),
      hasHealthInsuranceSelf: annualHealthInsurance == null
          ? profile.hasHealthInsuranceSelf
          : (_largerOptional(
                    profile.healthInsuranceSelfPremium,
                    annualHealthInsurance,
                  ) ??
                  0) >
              0,
      healthInsuranceSelfPremium: _largerOptional(
        profile.healthInsuranceSelfPremium,
        annualHealthInsurance,
      ),
    );
  }

  /// Builds the profile used for tax calculation. Confirmed payslip gross can
  /// replace CTC for this calculation without rewriting the user's saved CTC.
  UserProfile applyForTax(UserProfile profile) {
    return profile.copyWith(
      annualCTC: annualGrossSalary ?? profile.annualCTC,
    );
  }
}

int _larger(int current, int? detected) =>
    detected != null && detected > current ? detected : current;

int? _largerOptional(int? current, int? detected) {
  if (detected == null) return current;
  if (current == null || detected > current) return detected;
  return current;
}

PayslipTaxPrefill? payslipTaxPrefillFromDocuments(
  List<TaxDocument> documents, {
  int monthsWorked = 12,
}) {
  final months = normalizeJobDurationMonths(monthsWorked);
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
  final eligible80C = _sumWhere(
    deductions,
    (row) =>
        const {'employee_pf', 'voluntary_pf'}
            .contains(row['classification']?.toString()) ||
        _containsAny(
          row,
          const ['provident', 'cpf pc', 'vpf', 'life insurance', 'lic'],
        ),
  );
  final employeeNps = _sumWhere(
    deductions,
    (row) => _containsAny(
      row,
      const ['80ccd(1b)', '80ccd 1b', '80ccd_1b', '80ccd1b'],
    ),
  );
  final healthInsurance = _sumWhere(
    deductions,
    (row) =>
        row['classification']?.toString() == 'insurance' &&
        _containsAny(row, const ['80d', 'mediclaim']),
  );

  final prefill = PayslipTaxPrefill(
    documentId: document.id,
    documentName: document.displayName,
    payPeriod: _text(fields['payPeriod']) ?? 'latest confirmed month',
    annualGrossSalary: _annualize(gross, months),
    annualBasicSalary: _annualize(basic, months),
    annualHraReceived: _annualize(hra, months),
    annualProfessionalTax: _annualize(professionalTax, months),
    annualEligible80C: _annualize(eligible80C, months),
    annualEmployeeNps: _annualize(employeeNps, months),
    annualHealthInsurance: _annualize(healthInsurance, months),
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

int? _sumWhere(
  List<Map<String, dynamic>> rows,
  bool Function(Map<String, dynamic>) matches,
) {
  final matched = rows.where(matches).toList(growable: false);
  return matched.isEmpty ? null : _sum(matched);
}

bool _containsAny(Map<String, dynamic> row, List<String> terms) {
  final text =
      '${row['label'] ?? ''} ${row['canonicalKey'] ?? ''}'.toLowerCase();
  return terms.any(text.contains);
}

int? _annualize(int? monthlyValue, int months) =>
    monthlyValue == null || monthlyValue <= 0 ? null : monthlyValue * months;

int? _amount(Object? value) => value is num ? value.round() : null;

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
