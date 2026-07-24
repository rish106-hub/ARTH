import 'dart:convert';

import 'package:flutter/services.dart';

enum TaxYearId {
  fy2025_26,
  fy2026_27;

  String get wireName {
    switch (this) {
      case TaxYearId.fy2025_26:
        return 'fy_2025_26';
      case TaxYearId.fy2026_27:
        return 'fy_2026_27';
    }
  }

  String get assetPath => 'assets/tax_rules/$wireName.json';

  String get displayLabel {
    switch (this) {
      case TaxYearId.fy2025_26:
        return 'FY2025-26 Filing';
      case TaxYearId.fy2026_27:
        return 'FY2026-27 Planning';
    }
  }

  String get fyLabel {
    switch (this) {
      case TaxYearId.fy2025_26:
        return 'FY 2025-26';
      case TaxYearId.fy2026_27:
        return 'FY 2026-27';
    }
  }

  String get assessmentYear {
    switch (this) {
      case TaxYearId.fy2025_26:
        return 'AY 2026-27';
      case TaxYearId.fy2026_27:
        return 'AY 2027-28';
    }
  }

  DateTime get fyStart {
    switch (this) {
      case TaxYearId.fy2025_26:
        return DateTime(2025, 4, 1);
      case TaxYearId.fy2026_27:
        return DateTime(2026, 4, 1);
    }
  }

  DateTime get fyEnd {
    switch (this) {
      case TaxYearId.fy2025_26:
        return DateTime(2026, 3, 31);
      case TaxYearId.fy2026_27:
        return DateTime(2027, 3, 31);
    }
  }

  static TaxYearId fromWireName(String value) {
    return TaxYearId.values.firstWhere(
      (id) => id.wireName == value,
      orElse: () => throw FormatException('Unknown tax year id: $value'),
    );
  }
}

enum CalculationMode {
  filing,
  planning;

  static CalculationMode fromJson(String? value) {
    return value == 'planning'
        ? CalculationMode.planning
        : CalculationMode.filing;
  }
}

enum TaxAssumptionSeverity { info, caution }

class TaxAssumption {
  final String code;
  final String title;
  final String detail;
  final TaxAssumptionSeverity severity;

  const TaxAssumption({
    required this.code,
    required this.title,
    required this.detail,
    this.severity = TaxAssumptionSeverity.info,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'detail': detail,
        'severity': severity.name,
      };

  factory TaxAssumption.fromJson(Map<String, dynamic> json) {
    final severityName = json['severity'] as String? ?? 'info';
    return TaxAssumption(
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      severity: severityName == 'caution'
          ? TaxAssumptionSeverity.caution
          : TaxAssumptionSeverity.info,
    );
  }
}

class TaxSlab {
  final double from;
  final double to;
  final double rate;

  const TaxSlab({
    required this.from,
    required this.to,
    required this.rate,
  });

  factory TaxSlab.fromJson(Map<String, dynamic> json) => TaxSlab(
        from: (json['from'] as num).toDouble(),
        to: (json['to'] as num).toDouble(),
        rate: (json['rate'] as num).toDouble(),
      );
}

class RegimeRuleSet {
  final int standardDeduction;
  final int rebate87ALimit;
  final int rebate87AAmount;
  final List<TaxSlab> slabs;
  final List<TaxSlab>? slabs60To79;
  final List<TaxSlab>? slabs80Plus;
  final int professionalTaxDefault;

  const RegimeRuleSet({
    required this.standardDeduction,
    required this.rebate87ALimit,
    required this.rebate87AAmount,
    required this.slabs,
    this.slabs60To79,
    this.slabs80Plus,
    this.professionalTaxDefault = 0,
  });

  factory RegimeRuleSet.fromJson(Map<String, dynamic> json) {
    List<TaxSlab> parseRequiredSlabs(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((item) => TaxSlab.fromJson(item as Map<String, dynamic>))
            .toList();
    List<TaxSlab>? parseOptionalSlabs(String key) {
      final raw = json[key] as List<dynamic>?;
      if (raw == null) return null;
      final parsed = raw
          .map((item) => TaxSlab.fromJson(item as Map<String, dynamic>))
          .toList();
      return parsed.isEmpty ? null : parsed;
    }

    final regularSlabs = parseRequiredSlabs('slabs');

    return RegimeRuleSet(
      standardDeduction: json['standard_deduction'] as int? ?? 0,
      professionalTaxDefault: json['professional_tax_default'] as int? ?? 0,
      rebate87ALimit: json['rebate_87a_limit'] as int? ?? 0,
      rebate87AAmount: json['rebate_87a_amount'] as int? ?? 0,
      slabs: regularSlabs.isNotEmpty
          ? regularSlabs
          : parseRequiredSlabs('slabs_below_60'),
      slabs60To79: parseOptionalSlabs('slabs_60_to_79'),
      slabs80Plus: parseOptionalSlabs('slabs_80_plus'),
    );
  }
}

class IncomeGuidanceItem {
  final String range;
  final String recommendation;
  final String reason;
  final String tone;

  const IncomeGuidanceItem({
    required this.range,
    required this.recommendation,
    required this.reason,
    required this.tone,
  });

  factory IncomeGuidanceItem.fromJson(Map<String, dynamic> json) {
    return IncomeGuidanceItem(
      range: json['range'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      tone: json['tone'] as String? ?? 'muted',
    );
  }
}

class TaxRuleSet {
  final TaxYearId id;
  final CalculationMode calculationMode;
  final String displayLabel;
  final String fyLabel;
  final String assessmentYear;
  final String financeAct;
  final String legalBasis;
  final String effectiveFrom;
  final String effectiveTo;
  final List<String> sourceUrls;
  final double cessRate;
  final RegimeRuleSet newRegime;
  final RegimeRuleSet oldRegime;
  final Map<String, int> deductionCaps;
  final List<IncomeGuidanceItem> incomeGuidance;

  /// Cities that qualify for the 50% HRA exemption (vs 40% elsewhere). This is
  /// year-dependent: FY2026-27 expanded the list from 4 to 8 metros (Rule 279).
  final List<String> hraMetroCities;

  const TaxRuleSet({
    required this.id,
    required this.calculationMode,
    required this.displayLabel,
    required this.fyLabel,
    required this.assessmentYear,
    required this.financeAct,
    required this.legalBasis,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.sourceUrls,
    required this.cessRate,
    required this.newRegime,
    required this.oldRegime,
    required this.deductionCaps,
    required this.incomeGuidance,
    this.hraMetroCities = const [],
  });

  /// Whether [city] qualifies for the 50% HRA metro rate under this year's
  /// rules. Case-insensitive.
  bool isHraMetro(String city) {
    final target = city.trim().toLowerCase();
    return hraMetroCities.any((c) => c.toLowerCase() == target);
  }

  bool get isFiling => calculationMode == CalculationMode.filing;

  String get compactLegalLabel => '$displayLabel • $assessmentYear';

  factory TaxRuleSet.fromJson(Map<String, dynamic> json) {
    final deductions = json['deductions'] as Map<String, dynamic>? ?? {};
    return TaxRuleSet(
      id: TaxYearId.fromWireName(json['id'] as String? ?? ''),
      calculationMode: CalculationMode.fromJson(
        json['calculation_mode'] as String?,
      ),
      displayLabel: json['display_label'] as String? ?? '',
      fyLabel: json['fy_label'] as String? ?? '',
      assessmentYear: json['assessment_year'] as String? ?? '',
      financeAct: json['finance_act'] as String? ?? '',
      legalBasis: json['legal_basis'] as String? ?? '',
      effectiveFrom: json['effective_from'] as String? ?? '',
      effectiveTo: json['effective_to'] as String? ?? '',
      sourceUrls: (json['source_urls'] as List<dynamic>? ?? []).cast<String>(),
      cessRate: (json['cess_rate'] as num? ?? 0.04).toDouble(),
      newRegime:
          RegimeRuleSet.fromJson(json['new_regime'] as Map<String, dynamic>),
      oldRegime:
          RegimeRuleSet.fromJson(json['old_regime'] as Map<String, dynamic>),
      deductionCaps: {
        for (final entry in deductions.entries)
          entry.key: (entry.value as num).toInt(),
      },
      incomeGuidance: (json['income_guidance'] as List<dynamic>? ?? [])
          .map((item) => IncomeGuidanceItem.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(),
      hraMetroCities: (json['hra_metro_cities'] as List<dynamic>? ?? const [])
          .map((c) => c.toString())
          .toList(),
    );
  }

  static Future<TaxRuleSet> load(TaxYearId id) async {
    final raw = await rootBundle.loadString(id.assetPath);
    return TaxRuleSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class TaxComputationTrace {
  final double oldTaxBeforeCess;
  final double newTaxBeforeCess;
  final double oldSurcharge;
  final double newSurcharge;
  final double oldCess;
  final double newCess;

  const TaxComputationTrace({
    required this.oldTaxBeforeCess,
    required this.newTaxBeforeCess,
    required this.oldSurcharge,
    required this.newSurcharge,
    required this.oldCess,
    required this.newCess,
  });

  Map<String, dynamic> toJson() => {
        'oldTaxBeforeCess': oldTaxBeforeCess,
        'newTaxBeforeCess': newTaxBeforeCess,
        'oldSurcharge': oldSurcharge,
        'newSurcharge': newSurcharge,
        'oldCess': oldCess,
        'newCess': newCess,
      };

  factory TaxComputationTrace.fromJson(Map<String, dynamic> json) {
    double read(String key) => (json[key] as num? ?? 0).toDouble();
    return TaxComputationTrace(
      oldTaxBeforeCess: read('oldTaxBeforeCess'),
      newTaxBeforeCess: read('newTaxBeforeCess'),
      oldSurcharge: read('oldSurcharge'),
      newSurcharge: read('newSurcharge'),
      oldCess: read('oldCess'),
      newCess: read('newCess'),
    );
  }
}
