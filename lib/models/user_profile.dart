import 'dart:convert';
import 'package:flutter/foundation.dart';

enum EmploymentType { salaried, selfEmployed }

/// Allowed job/income durations within a financial year (months).
const List<int> kJobDurationOptions = [3, 6, 9, 12];

/// Keep saved custom durations valid for salary annualisation.
int normalizeJobDurationMonths(int value) {
  return value.clamp(1, 12);
}

enum AgeGroup { below30, age30to45, age45to60, above60, above80 }

enum PropertyType { selfOccupied, letOut }

EmploymentType _employmentTypeFromJson(dynamic value) {
  if (value is String) {
    return EmploymentType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => EmploymentType.salaried,
    );
  }
  if (value is int && value >= 0 && value < EmploymentType.values.length) {
    return EmploymentType.values[value];
  }
  return EmploymentType.salaried;
}

AgeGroup _ageGroupFromJson(dynamic value) {
  if (value is String) {
    return AgeGroup.values.firstWhere(
      (group) => group.name == value,
      orElse: () => AgeGroup.below30,
    );
  }
  if (value is int && value >= 0 && value < AgeGroup.values.length) {
    return AgeGroup.values[value];
  }
  return AgeGroup.below30;
}

PropertyType? _propertyTypeFromJson(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    return PropertyType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => PropertyType.selfOccupied,
    );
  }
  if (value is int && value >= 0 && value < PropertyType.values.length) {
    return PropertyType.values[value];
  }
  return null;
}

extension AgeGroupExtension on AgeGroup {
  String get label {
    switch (this) {
      case AgeGroup.below30:
        return 'Below 30';
      case AgeGroup.age30to45:
        return '30 – 45';
      case AgeGroup.age45to60:
        return '45 – 60';
      case AgeGroup.above60:
        return '60 – 79';
      case AgeGroup.above80:
        return '80+';
    }
  }

  bool get isSenior => this == AgeGroup.above60 || this == AgeGroup.above80;
  bool get isSuperSenior => this == AgeGroup.above80;
  bool get isBelow60 => !isSenior;

  // Approximate mid-age for calculations
  int get midAge {
    switch (this) {
      case AgeGroup.below30:
        return 27;
      case AgeGroup.age30to45:
        return 37;
      case AgeGroup.age45to60:
        return 52;
      case AgeGroup.above60:
        return 65;
      case AgeGroup.above80:
        return 82;
    }
  }
}

@immutable
class UserProfile {
  // Personal info
  final String name;
  final String email;

  // Q01
  final int annualCTC; // in rupees

  // Q02
  final EmploymentType employmentType;
  final String employerName;

  // Duration of this job/income engagement within the financial year.
  // Not every job runs the full year. Common options are 3, 6, 9 and 12
  // months, with any one-to-twelve-month duration supported.
  // Drives salary annualization (monthly figure × jobDurationMonths).
  final int jobDurationMonths;

  // Q03
  final String city;
  final bool isMetroCity;

  // Q04
  final bool paysRent;
  final int monthlyRent; // in rupees

  // Q05
  final bool hasHRA;

  // Q06
  final int invested80C; // in rupees (0 to 150000)

  // Q07
  final bool hasHomeLoan;
  final PropertyType? propertyType;
  final int homeLoanInterest; // annual interest in rupees

  // Q08
  final bool hasNPS;
  final int npsExtraContribution; // 80CCD(1B) extra contribution

  // Q09 — health insurance
  final bool hasHealthInsuranceSelf;
  final bool hasHealthInsuranceParents;
  final bool parentsAbove60;

  // Q10
  final bool hasEducationLoan;
  final int educationLoanRepaymentYear; // 1–8
  final int educationLoanInterest; // annual interest

  // Q11
  final bool hasDonations;
  final int donationAmount;

  // Q12
  final AgeGroup ageGroup;

  // Optional exactness inputs. Null means "not collected yet" and the engine
  // will use a conservative app assumption with a visible assumption tag.
  final int? actualBasicSalary;
  final int? actualHraReceived;
  final int? actualProfessionalTax;
  final int? healthInsuranceSelfPremium;
  final int? healthInsuranceParentsPremium;
  final int? savingsInterest;
  final int? fdInterest;
  final int? employerNpsContribution;
  final int? donationDeductionRatePercent;

  // Derived
  bool get paysRentNoHRA => paysRent && !hasHRA;
  bool get hasHomeLoanSelfOccupied =>
      hasHomeLoan && propertyType == PropertyType.selfOccupied;
  bool get ageBelow60 => ageGroup.isBelow60;
  bool get ageAbove60 => ageGroup.isSenior;
  bool get ageAbove80 => ageGroup.isSuperSenior;

  // Approximate basic salary = 40% of CTC (common approximation)
  int get approximateBasicSalary =>
      actualBasicSalary ?? (annualCTC * 0.40).round();

  const UserProfile({
    this.name = '',
    this.email = '',
    this.annualCTC = 1000000,
    this.employmentType = EmploymentType.salaried,
    this.employerName = '',
    this.jobDurationMonths = 12,
    this.city = 'Bengaluru',
    this.isMetroCity = false,
    this.paysRent = false,
    this.monthlyRent = 0,
    this.hasHRA = false,
    this.invested80C = 0,
    this.hasHomeLoan = false,
    this.propertyType,
    this.homeLoanInterest = 0,
    this.hasNPS = false,
    this.npsExtraContribution = 0,
    this.hasHealthInsuranceSelf = false,
    this.hasHealthInsuranceParents = false,
    this.parentsAbove60 = false,
    this.hasEducationLoan = false,
    this.educationLoanRepaymentYear = 1,
    this.educationLoanInterest = 0,
    this.hasDonations = false,
    this.donationAmount = 0,
    this.ageGroup = AgeGroup.below30,
    this.actualBasicSalary,
    this.actualHraReceived,
    this.actualProfessionalTax,
    this.healthInsuranceSelfPremium,
    this.healthInsuranceParentsPremium,
    this.savingsInterest,
    this.fdInterest,
    this.employerNpsContribution,
    this.donationDeductionRatePercent,
  });

  // Sentinel so callers can explicitly pass null for nullable fields.
  static const _unset = Object();

  UserProfile copyWith({
    String? name,
    String? email,
    int? annualCTC,
    EmploymentType? employmentType,
    String? employerName,
    int? jobDurationMonths,
    String? city,
    bool? isMetroCity,
    bool? paysRent,
    int? monthlyRent,
    bool? hasHRA,
    int? invested80C,
    bool? hasHomeLoan,
    Object? propertyType = _unset, // <-- Object? so null can be passed
    int? homeLoanInterest,
    bool? hasNPS,
    int? npsExtraContribution,
    bool? hasHealthInsuranceSelf,
    bool? hasHealthInsuranceParents,
    bool? parentsAbove60,
    bool? hasEducationLoan,
    int? educationLoanRepaymentYear,
    int? educationLoanInterest,
    bool? hasDonations,
    int? donationAmount,
    AgeGroup? ageGroup,
    Object? actualBasicSalary = _unset,
    Object? actualHraReceived = _unset,
    Object? actualProfessionalTax = _unset,
    Object? healthInsuranceSelfPremium = _unset,
    Object? healthInsuranceParentsPremium = _unset,
    Object? savingsInterest = _unset,
    Object? fdInterest = _unset,
    Object? employerNpsContribution = _unset,
    Object? donationDeductionRatePercent = _unset,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      annualCTC: annualCTC ?? this.annualCTC,
      employmentType: employmentType ?? this.employmentType,
      employerName: employerName ?? this.employerName,
      jobDurationMonths: jobDurationMonths ?? this.jobDurationMonths,
      city: city ?? this.city,
      isMetroCity: isMetroCity ?? this.isMetroCity,
      paysRent: paysRent ?? this.paysRent,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      hasHRA: hasHRA ?? this.hasHRA,
      invested80C: invested80C ?? this.invested80C,
      hasHomeLoan: hasHomeLoan ?? this.hasHomeLoan,
      propertyType: identical(propertyType, _unset)
          ? this.propertyType
          : propertyType as PropertyType?,
      homeLoanInterest: homeLoanInterest ?? this.homeLoanInterest,
      hasNPS: hasNPS ?? this.hasNPS,
      npsExtraContribution: npsExtraContribution ?? this.npsExtraContribution,
      hasHealthInsuranceSelf:
          hasHealthInsuranceSelf ?? this.hasHealthInsuranceSelf,
      hasHealthInsuranceParents:
          hasHealthInsuranceParents ?? this.hasHealthInsuranceParents,
      parentsAbove60: parentsAbove60 ?? this.parentsAbove60,
      hasEducationLoan: hasEducationLoan ?? this.hasEducationLoan,
      educationLoanRepaymentYear:
          educationLoanRepaymentYear ?? this.educationLoanRepaymentYear,
      educationLoanInterest:
          educationLoanInterest ?? this.educationLoanInterest,
      hasDonations: hasDonations ?? this.hasDonations,
      donationAmount: donationAmount ?? this.donationAmount,
      ageGroup: ageGroup ?? this.ageGroup,
      actualBasicSalary: identical(actualBasicSalary, _unset)
          ? this.actualBasicSalary
          : actualBasicSalary as int?,
      actualHraReceived: identical(actualHraReceived, _unset)
          ? this.actualHraReceived
          : actualHraReceived as int?,
      actualProfessionalTax: identical(actualProfessionalTax, _unset)
          ? this.actualProfessionalTax
          : actualProfessionalTax as int?,
      healthInsuranceSelfPremium: identical(healthInsuranceSelfPremium, _unset)
          ? this.healthInsuranceSelfPremium
          : healthInsuranceSelfPremium as int?,
      healthInsuranceParentsPremium:
          identical(healthInsuranceParentsPremium, _unset)
              ? this.healthInsuranceParentsPremium
              : healthInsuranceParentsPremium as int?,
      savingsInterest: identical(savingsInterest, _unset)
          ? this.savingsInterest
          : savingsInterest as int?,
      fdInterest:
          identical(fdInterest, _unset) ? this.fdInterest : fdInterest as int?,
      employerNpsContribution: identical(employerNpsContribution, _unset)
          ? this.employerNpsContribution
          : employerNpsContribution as int?,
      donationDeductionRatePercent:
          identical(donationDeductionRatePercent, _unset)
              ? this.donationDeductionRatePercent
              : donationDeductionRatePercent as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'annualCTC': annualCTC,
        'employmentType': employmentType.name,
        'employerName': employerName,
        'jobDurationMonths': jobDurationMonths,
        'city': city,
        'isMetroCity': isMetroCity,
        'paysRent': paysRent,
        'monthlyRent': monthlyRent,
        'hasHRA': hasHRA,
        'invested80C': invested80C,
        'hasHomeLoan': hasHomeLoan,
        'propertyType': propertyType?.name,
        'homeLoanInterest': homeLoanInterest,
        'hasNPS': hasNPS,
        'npsExtraContribution': npsExtraContribution,
        'hasHealthInsuranceSelf': hasHealthInsuranceSelf,
        'hasHealthInsuranceParents': hasHealthInsuranceParents,
        'parentsAbove60': parentsAbove60,
        'hasEducationLoan': hasEducationLoan,
        'educationLoanRepaymentYear': educationLoanRepaymentYear,
        'educationLoanInterest': educationLoanInterest,
        'hasDonations': hasDonations,
        'donationAmount': donationAmount,
        'ageGroup': ageGroup.name,
        'actualBasicSalary': actualBasicSalary,
        'actualHraReceived': actualHraReceived,
        'actualProfessionalTax': actualProfessionalTax,
        'healthInsuranceSelfPremium': healthInsuranceSelfPremium,
        'healthInsuranceParentsPremium': healthInsuranceParentsPremium,
        'savingsInterest': savingsInterest,
        'fdInterest': fdInterest,
        'employerNpsContribution': employerNpsContribution,
        'donationDeductionRatePercent': donationDeductionRatePercent,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) =>
        (json[key] as num?)?.round() ?? fallback;
    int? readOptionalInt(String key) => (json[key] as num?)?.round();

    return UserProfile(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      annualCTC: readInt('annualCTC', 1000000),
      employmentType: _employmentTypeFromJson(json['employmentType']),
      employerName: json['employerName']?.toString() ?? '',
      jobDurationMonths:
          normalizeJobDurationMonths(readInt('jobDurationMonths', 12)),
      city: json['city'] ?? 'Bengaluru',
      isMetroCity: json['isMetroCity'] ?? false,
      paysRent: json['paysRent'] ?? false,
      monthlyRent: readInt('monthlyRent', 0),
      hasHRA: json['hasHRA'] ?? false,
      invested80C: readInt('invested80C', 0),
      hasHomeLoan: json['hasHomeLoan'] ?? false,
      propertyType: _propertyTypeFromJson(json['propertyType']),
      homeLoanInterest: readInt('homeLoanInterest', 0),
      hasNPS: json['hasNPS'] ?? false,
      npsExtraContribution: readInt('npsExtraContribution', 0),
      hasHealthInsuranceSelf: json['hasHealthInsuranceSelf'] ?? false,
      hasHealthInsuranceParents: json['hasHealthInsuranceParents'] ?? false,
      parentsAbove60: json['parentsAbove60'] ?? false,
      hasEducationLoan: json['hasEducationLoan'] ?? false,
      educationLoanRepaymentYear: readInt('educationLoanRepaymentYear', 1),
      educationLoanInterest: readInt('educationLoanInterest', 0),
      hasDonations: json['hasDonations'] ?? false,
      donationAmount: readInt('donationAmount', 0),
      ageGroup: _ageGroupFromJson(json['ageGroup']),
      actualBasicSalary: readOptionalInt('actualBasicSalary'),
      actualHraReceived: readOptionalInt('actualHraReceived'),
      actualProfessionalTax: readOptionalInt('actualProfessionalTax'),
      healthInsuranceSelfPremium: readOptionalInt('healthInsuranceSelfPremium'),
      healthInsuranceParentsPremium:
          readOptionalInt('healthInsuranceParentsPremium'),
      savingsInterest: readOptionalInt('savingsInterest'),
      fdInterest: readOptionalInt('fdInterest'),
      employerNpsContribution: readOptionalInt('employerNpsContribution'),
      donationDeductionRatePercent:
          readOptionalInt('donationDeductionRatePercent'),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  static UserProfile fromJsonString(String s) =>
      UserProfile.fromJson(jsonDecode(s));
}
