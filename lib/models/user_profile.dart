import 'dart:convert';
import 'package:flutter/foundation.dart';

enum EmploymentType { salaried, selfEmployed }

enum AgeGroup { below30, age30to45, age45to60, above60 }

enum PropertyType { selfOccupied, letOut }

extension AgeGroupExtension on AgeGroup {
  String get label {
    switch (this) {
      case AgeGroup.below30: return 'Below 30';
      case AgeGroup.age30to45: return '30 – 45';
      case AgeGroup.age45to60: return '45 – 60';
      case AgeGroup.above60: return 'Above 60';
    }
  }

  bool get isSenior => this == AgeGroup.above60;
  bool get isBelow60 => this != AgeGroup.above60;

  // Approximate mid-age for calculations
  int get midAge {
    switch (this) {
      case AgeGroup.below30: return 27;
      case AgeGroup.age30to45: return 37;
      case AgeGroup.age45to60: return 52;
      case AgeGroup.above60: return 65;
    }
  }
}

@immutable
class UserProfile {
  // Q01
  final int annualCTC; // in rupees

  // Q02
  final EmploymentType employmentType;

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

  // Derived
  bool get paysRentNoHRA => paysRent && !hasHRA;
  bool get hasHomeLoanSelfOccupied => hasHomeLoan && propertyType == PropertyType.selfOccupied;
  bool get ageBelow60 => ageGroup.isBelow60;
  bool get ageAbove60 => ageGroup.isSenior;

  // Approximate basic salary = 40% of CTC (common approximation)
  int get approximateBasicSalary => (annualCTC * 0.40).round();

  const UserProfile({
    this.annualCTC = 1000000,
    this.employmentType = EmploymentType.salaried,
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
  });

  UserProfile copyWith({
    int? annualCTC,
    EmploymentType? employmentType,
    String? city,
    bool? isMetroCity,
    bool? paysRent,
    int? monthlyRent,
    bool? hasHRA,
    int? invested80C,
    bool? hasHomeLoan,
    PropertyType? propertyType,
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
  }) {
    return UserProfile(
      annualCTC: annualCTC ?? this.annualCTC,
      employmentType: employmentType ?? this.employmentType,
      city: city ?? this.city,
      isMetroCity: isMetroCity ?? this.isMetroCity,
      paysRent: paysRent ?? this.paysRent,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      hasHRA: hasHRA ?? this.hasHRA,
      invested80C: invested80C ?? this.invested80C,
      hasHomeLoan: hasHomeLoan ?? this.hasHomeLoan,
      propertyType: propertyType ?? this.propertyType,
      homeLoanInterest: homeLoanInterest ?? this.homeLoanInterest,
      hasNPS: hasNPS ?? this.hasNPS,
      npsExtraContribution: npsExtraContribution ?? this.npsExtraContribution,
      hasHealthInsuranceSelf: hasHealthInsuranceSelf ?? this.hasHealthInsuranceSelf,
      hasHealthInsuranceParents: hasHealthInsuranceParents ?? this.hasHealthInsuranceParents,
      parentsAbove60: parentsAbove60 ?? this.parentsAbove60,
      hasEducationLoan: hasEducationLoan ?? this.hasEducationLoan,
      educationLoanRepaymentYear: educationLoanRepaymentYear ?? this.educationLoanRepaymentYear,
      educationLoanInterest: educationLoanInterest ?? this.educationLoanInterest,
      hasDonations: hasDonations ?? this.hasDonations,
      donationAmount: donationAmount ?? this.donationAmount,
      ageGroup: ageGroup ?? this.ageGroup,
    );
  }

  Map<String, dynamic> toJson() => {
    'annualCTC': annualCTC,
    'employmentType': employmentType.index,
    'city': city,
    'isMetroCity': isMetroCity,
    'paysRent': paysRent,
    'monthlyRent': monthlyRent,
    'hasHRA': hasHRA,
    'invested80C': invested80C,
    'hasHomeLoan': hasHomeLoan,
    'propertyType': propertyType?.index,
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
    'ageGroup': ageGroup.index,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    annualCTC: json['annualCTC'] ?? 1000000,
    employmentType: EmploymentType.values[json['employmentType'] ?? 0],
    city: json['city'] ?? 'Bengaluru',
    isMetroCity: json['isMetroCity'] ?? false,
    paysRent: json['paysRent'] ?? false,
    monthlyRent: json['monthlyRent'] ?? 0,
    hasHRA: json['hasHRA'] ?? false,
    invested80C: json['invested80C'] ?? 0,
    hasHomeLoan: json['hasHomeLoan'] ?? false,
    propertyType: json['propertyType'] != null ? PropertyType.values[json['propertyType']] : null,
    homeLoanInterest: json['homeLoanInterest'] ?? 0,
    hasNPS: json['hasNPS'] ?? false,
    npsExtraContribution: json['npsExtraContribution'] ?? 0,
    hasHealthInsuranceSelf: json['hasHealthInsuranceSelf'] ?? false,
    hasHealthInsuranceParents: json['hasHealthInsuranceParents'] ?? false,
    parentsAbove60: json['parentsAbove60'] ?? false,
    hasEducationLoan: json['hasEducationLoan'] ?? false,
    educationLoanRepaymentYear: json['educationLoanRepaymentYear'] ?? 1,
    educationLoanInterest: json['educationLoanInterest'] ?? 0,
    hasDonations: json['hasDonations'] ?? false,
    donationAmount: json['donationAmount'] ?? 0,
    ageGroup: AgeGroup.values[json['ageGroup'] ?? 0],
  );

  String toJsonString() => jsonEncode(toJson());
  static UserProfile fromJsonString(String s) => UserProfile.fromJson(jsonDecode(s));
}
