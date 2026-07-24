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

/// How the user wants the two regimes handled. `auto` lets the app decide
/// (and skip deduction questions when the new regime is a clear win).
enum RegimePreference { auto, newRegime, oldRegime }

/// Residential status — determines scope of taxable income and some reliefs.
enum ResidentialStatus { resident, rnor, nonResident }

/// Presumptive-taxation scheme for self-employed income.
enum BusinessPresumption {
  none,
  profession44ADA, // professionals: 50% of gross receipts
  business44AD, // small business: 8% of turnover (6% digital)
}

/// Disability severity band (per 80U / 80DD): moderate = 40–79%, severe = 80%+.
enum DisabilityLevel { none, moderate, severe }

T _enumFromName<T>(
    List<T> values, String Function(T) name, dynamic raw, T fallback) {
  if (raw is String) {
    for (final v in values) {
      if (name(v) == raw) return v;
    }
  }
  return fallback;
}

RegimePreference _regimePreferenceFromJson(dynamic value) {
  if (value is String) {
    for (final r in RegimePreference.values) {
      if (r.name == value) return r;
    }
  }
  return RegimePreference.auto;
}

/// 80G donation buckets. Each maps to a statutory deduction rate and whether
/// the 10%-of-adjusted-GTI qualifying limit applies.
enum DonationCategory {
  /// PM CARES, PMNRF, National Defence Fund, etc. — 100%, no qualifying limit.
  hundredNoLimit,

  /// e.g. certain government/state funds — 100%, subject to the 10% limit.
  hundredWithLimit,

  /// e.g. PM Drought Relief and similar — 50%, no qualifying limit.
  fiftyNoLimit,

  /// NGOs, charitable / religious (temple) trusts with 80G — 50%, 10% limit.
  fiftyWithLimit,
}

extension DonationCategoryX on DonationCategory {
  /// Fraction of the eligible donation that is deductible.
  double get rate => switch (this) {
        DonationCategory.hundredNoLimit => 1.0,
        DonationCategory.hundredWithLimit => 1.0,
        DonationCategory.fiftyNoLimit => 0.5,
        DonationCategory.fiftyWithLimit => 0.5,
      };

  /// Whether the 10%-of-adjusted-GTI qualifying limit caps the eligible amount.
  bool get hasQualifyingLimit => switch (this) {
        DonationCategory.hundredWithLimit => true,
        DonationCategory.fiftyWithLimit => true,
        _ => false,
      };

  int get ratePercent => (rate * 100).round();
}

DonationCategory? _donationCategoryFromJson(dynamic value) {
  if (value is String) {
    for (final c in DonationCategory.values) {
      if (c.name == value) return c;
    }
  }
  return null;
}

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
  final DonationCategory? donationCategory;
  final bool donationInCash;

  // Q12
  final AgeGroup ageGroup;

  // Regime intent — gates whether deduction questions are asked.
  final RegimePreference regimePreference;

  // ── Other income (taxed alongside / at special rates) ──
  final ResidentialStatus residentialStatus;
  final int stcgEquity111A; // short-term gains on listed equity (111A)
  final int ltcgEquity112A; // long-term gains on listed equity (112A)
  final int ltcgOther112; // long-term gains on other assets (112)
  final int
      otherSlabIncome; // misc income taxed at slab (non-equity STCG, etc.)
  final int rentalIncomeAnnual; // gross annual rent from let-out property
  final int letOutHomeLoanInterest; // interest on a let-out property loan
  final BusinessPresumption businessPresumption;
  final int businessGrossReceipts; // turnover / gross receipts for presumptive

  // ── Additional deductions ──
  final DisabilityLevel selfDisability; // 80U
  final DisabilityLevel dependentDisability; // 80DD
  final int? criticalIllnessExpense; // 80DDB
  final bool criticalIllnessPatientSenior;
  final int evLoanInterest; // 80EEB (loans sanctioned Apr 2019 – Mar 2023)
  final int agniveerCorpus; // 80CCH

  // Optional exactness inputs. Null means "not collected yet" and the engine
  // will use a conservative app assumption with a visible assumption tag.
  final int? actualBasicSalary;
  final int? actualHraReceived;
  final int? actualProfessionalTax;
  final int? healthInsuranceSelfPremium;
  final int? healthInsuranceParentsPremium;
  final int? preventiveHealthCheckup;
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
    this.donationCategory,
    this.donationInCash = false,
    this.ageGroup = AgeGroup.below30,
    this.regimePreference = RegimePreference.auto,
    this.residentialStatus = ResidentialStatus.resident,
    this.stcgEquity111A = 0,
    this.ltcgEquity112A = 0,
    this.ltcgOther112 = 0,
    this.otherSlabIncome = 0,
    this.rentalIncomeAnnual = 0,
    this.letOutHomeLoanInterest = 0,
    this.businessPresumption = BusinessPresumption.none,
    this.businessGrossReceipts = 0,
    this.selfDisability = DisabilityLevel.none,
    this.dependentDisability = DisabilityLevel.none,
    this.criticalIllnessExpense,
    this.criticalIllnessPatientSenior = false,
    this.evLoanInterest = 0,
    this.agniveerCorpus = 0,
    this.actualBasicSalary,
    this.actualHraReceived,
    this.actualProfessionalTax,
    this.healthInsuranceSelfPremium,
    this.healthInsuranceParentsPremium,
    this.preventiveHealthCheckup,
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
    Object? donationCategory = _unset,
    bool? donationInCash,
    AgeGroup? ageGroup,
    RegimePreference? regimePreference,
    ResidentialStatus? residentialStatus,
    int? stcgEquity111A,
    int? ltcgEquity112A,
    int? ltcgOther112,
    int? otherSlabIncome,
    int? rentalIncomeAnnual,
    int? letOutHomeLoanInterest,
    BusinessPresumption? businessPresumption,
    int? businessGrossReceipts,
    DisabilityLevel? selfDisability,
    DisabilityLevel? dependentDisability,
    Object? criticalIllnessExpense = _unset,
    bool? criticalIllnessPatientSenior,
    int? evLoanInterest,
    int? agniveerCorpus,
    Object? actualBasicSalary = _unset,
    Object? actualHraReceived = _unset,
    Object? actualProfessionalTax = _unset,
    Object? healthInsuranceSelfPremium = _unset,
    Object? healthInsuranceParentsPremium = _unset,
    Object? preventiveHealthCheckup = _unset,
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
      donationCategory: identical(donationCategory, _unset)
          ? this.donationCategory
          : donationCategory as DonationCategory?,
      donationInCash: donationInCash ?? this.donationInCash,
      ageGroup: ageGroup ?? this.ageGroup,
      regimePreference: regimePreference ?? this.regimePreference,
      residentialStatus: residentialStatus ?? this.residentialStatus,
      stcgEquity111A: stcgEquity111A ?? this.stcgEquity111A,
      ltcgEquity112A: ltcgEquity112A ?? this.ltcgEquity112A,
      ltcgOther112: ltcgOther112 ?? this.ltcgOther112,
      otherSlabIncome: otherSlabIncome ?? this.otherSlabIncome,
      rentalIncomeAnnual: rentalIncomeAnnual ?? this.rentalIncomeAnnual,
      letOutHomeLoanInterest:
          letOutHomeLoanInterest ?? this.letOutHomeLoanInterest,
      businessPresumption: businessPresumption ?? this.businessPresumption,
      businessGrossReceipts:
          businessGrossReceipts ?? this.businessGrossReceipts,
      selfDisability: selfDisability ?? this.selfDisability,
      dependentDisability: dependentDisability ?? this.dependentDisability,
      criticalIllnessExpense: identical(criticalIllnessExpense, _unset)
          ? this.criticalIllnessExpense
          : criticalIllnessExpense as int?,
      criticalIllnessPatientSenior:
          criticalIllnessPatientSenior ?? this.criticalIllnessPatientSenior,
      evLoanInterest: evLoanInterest ?? this.evLoanInterest,
      agniveerCorpus: agniveerCorpus ?? this.agniveerCorpus,
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
      preventiveHealthCheckup: identical(preventiveHealthCheckup, _unset)
          ? this.preventiveHealthCheckup
          : preventiveHealthCheckup as int?,
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
        'donationCategory': donationCategory?.name,
        'donationInCash': donationInCash,
        'ageGroup': ageGroup.name,
        'regimePreference': regimePreference.name,
        'residentialStatus': residentialStatus.name,
        'stcgEquity111A': stcgEquity111A,
        'ltcgEquity112A': ltcgEquity112A,
        'ltcgOther112': ltcgOther112,
        'otherSlabIncome': otherSlabIncome,
        'rentalIncomeAnnual': rentalIncomeAnnual,
        'letOutHomeLoanInterest': letOutHomeLoanInterest,
        'businessPresumption': businessPresumption.name,
        'businessGrossReceipts': businessGrossReceipts,
        'selfDisability': selfDisability.name,
        'dependentDisability': dependentDisability.name,
        'criticalIllnessExpense': criticalIllnessExpense,
        'criticalIllnessPatientSenior': criticalIllnessPatientSenior,
        'evLoanInterest': evLoanInterest,
        'agniveerCorpus': agniveerCorpus,
        'actualBasicSalary': actualBasicSalary,
        'actualHraReceived': actualHraReceived,
        'actualProfessionalTax': actualProfessionalTax,
        'healthInsuranceSelfPremium': healthInsuranceSelfPremium,
        'healthInsuranceParentsPremium': healthInsuranceParentsPremium,
        'preventiveHealthCheckup': preventiveHealthCheckup,
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
      donationCategory: _donationCategoryFromJson(json['donationCategory']),
      donationInCash: json['donationInCash'] ?? false,
      ageGroup: _ageGroupFromJson(json['ageGroup']),
      regimePreference: _regimePreferenceFromJson(json['regimePreference']),
      residentialStatus: _enumFromName(ResidentialStatus.values, (v) => v.name,
          json['residentialStatus'], ResidentialStatus.resident),
      stcgEquity111A: readInt('stcgEquity111A', 0),
      ltcgEquity112A: readInt('ltcgEquity112A', 0),
      ltcgOther112: readInt('ltcgOther112', 0),
      otherSlabIncome: readInt('otherSlabIncome', 0),
      rentalIncomeAnnual: readInt('rentalIncomeAnnual', 0),
      letOutHomeLoanInterest: readInt('letOutHomeLoanInterest', 0),
      businessPresumption: _enumFromName(BusinessPresumption.values,
          (v) => v.name, json['businessPresumption'], BusinessPresumption.none),
      businessGrossReceipts: readInt('businessGrossReceipts', 0),
      selfDisability: _enumFromName(DisabilityLevel.values, (v) => v.name,
          json['selfDisability'], DisabilityLevel.none),
      dependentDisability: _enumFromName(DisabilityLevel.values, (v) => v.name,
          json['dependentDisability'], DisabilityLevel.none),
      criticalIllnessExpense: readOptionalInt('criticalIllnessExpense'),
      criticalIllnessPatientSenior:
          json['criticalIllnessPatientSenior'] ?? false,
      evLoanInterest: readInt('evLoanInterest', 0),
      agniveerCorpus: readInt('agniveerCorpus', 0),
      actualBasicSalary: readOptionalInt('actualBasicSalary'),
      actualHraReceived: readOptionalInt('actualHraReceived'),
      actualProfessionalTax: readOptionalInt('actualProfessionalTax'),
      healthInsuranceSelfPremium: readOptionalInt('healthInsuranceSelfPremium'),
      healthInsuranceParentsPremium:
          readOptionalInt('healthInsuranceParentsPremium'),
      preventiveHealthCheckup: readOptionalInt('preventiveHealthCheckup'),
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
