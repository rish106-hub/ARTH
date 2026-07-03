import 'gap_card.dart';
import 'tax_rule_set.dart';

enum TaxRegime { newRegime, oldRegime }

class TaxResult {
  final String ruleSetId;
  final String ruleSetLabel;
  final String assessmentYear;
  final CalculationMode calculationMode;
  final double oldRegimeTax;
  final double newRegimeTax;
  final double oldRegimeTaxableIncome;
  final double newRegimeTaxableIncome;
  final double totalDeductionsOld;
  final TaxRegime betterRegime;
  final double regimeSavings; // |old - new|
  final List<GapCard> gaps;
  final int totalGapAmount;
  final int deductionOpportunity;
  final int estimatedTaxBenefit;
  final int gapCount;
  final List<TaxAssumption> assumptions;
  final TaxComputationTrace trace;
  final int confidenceScore;

  const TaxResult({
    this.ruleSetId = 'fy_2025_26',
    this.ruleSetLabel = 'FY2025-26 Filing',
    this.assessmentYear = 'AY 2026-27',
    this.calculationMode = CalculationMode.filing,
    required this.oldRegimeTax,
    required this.newRegimeTax,
    required this.oldRegimeTaxableIncome,
    required this.newRegimeTaxableIncome,
    required this.totalDeductionsOld,
    required this.betterRegime,
    required this.regimeSavings,
    required this.gaps,
    required this.totalGapAmount,
    int? deductionOpportunity,
    this.estimatedTaxBenefit = 0,
    required this.gapCount,
    this.assumptions = const [],
    this.trace = const TaxComputationTrace(
      oldTaxBeforeCess: 0,
      newTaxBeforeCess: 0,
      oldSurcharge: 0,
      newSurcharge: 0,
      oldCess: 0,
      newCess: 0,
    ),
    this.confidenceScore = 70,
  }) : deductionOpportunity = deductionOpportunity ?? totalGapAmount;

  bool get isOldBetter => betterRegime == TaxRegime.oldRegime;

  double get currentTax =>
      betterRegime == TaxRegime.oldRegime ? oldRegimeTax : newRegimeTax;

  double get worseTax =>
      betterRegime == TaxRegime.oldRegime ? newRegimeTax : oldRegimeTax;

  String get betterRegimeLabel =>
      betterRegime == TaxRegime.oldRegime ? 'Old Regime' : 'New Regime';

  String get worseRegimeLabel =>
      betterRegime == TaxRegime.oldRegime ? 'New Regime' : 'Old Regime';

  String get confidenceLabel {
    if (confidenceScore >= 85) return 'High confidence';
    if (confidenceScore >= 65) return 'Medium confidence';
    return 'Needs more inputs';
  }

  Map<String, dynamic> toJson() => {
        'ruleSetId': ruleSetId,
        'ruleSetLabel': ruleSetLabel,
        'assessmentYear': assessmentYear,
        'calculationMode': calculationMode.name,
        'oldRegimeTax': oldRegimeTax,
        'newRegimeTax': newRegimeTax,
        'oldRegimeTaxableIncome': oldRegimeTaxableIncome,
        'newRegimeTaxableIncome': newRegimeTaxableIncome,
        'totalDeductionsOld': totalDeductionsOld,
        'betterRegime': betterRegime.name,
        'regimeSavings': regimeSavings,
        'gaps': gaps.map((g) => g.toJson()).toList(),
        'totalGapAmount': totalGapAmount,
        'deductionOpportunity': deductionOpportunity,
        'estimatedTaxBenefit': estimatedTaxBenefit,
        'gapCount': gapCount,
        'assumptions': assumptions.map((item) => item.toJson()).toList(),
        'trace': trace.toJson(),
        'confidenceScore': confidenceScore,
        'confidenceLabel': confidenceLabel,
      };

  factory TaxResult.fromJson(Map<String, dynamic> json) {
    final betterRegimeName = json['betterRegime'] as String? ?? 'newRegime';
    final calculationModeName = json['calculationMode'] as String? ?? 'filing';
    int readInt(String key) => (json[key] as num? ?? 0).round();
    final totalGapAmount = readInt('totalGapAmount');
    return TaxResult(
      ruleSetId: json['ruleSetId'] as String? ?? 'fy_2025_26',
      ruleSetLabel: json['ruleSetLabel'] as String? ?? 'FY2025-26 Filing',
      assessmentYear: json['assessmentYear'] as String? ?? 'AY 2026-27',
      calculationMode: calculationModeName == 'planning'
          ? CalculationMode.planning
          : CalculationMode.filing,
      oldRegimeTax: (json['oldRegimeTax'] as num).toDouble(),
      newRegimeTax: (json['newRegimeTax'] as num).toDouble(),
      oldRegimeTaxableIncome:
          (json['oldRegimeTaxableIncome'] as num).toDouble(),
      newRegimeTaxableIncome:
          (json['newRegimeTaxableIncome'] as num).toDouble(),
      totalDeductionsOld: (json['totalDeductionsOld'] as num).toDouble(),
      betterRegime: betterRegimeName == 'oldRegime'
          ? TaxRegime.oldRegime
          : TaxRegime.newRegime,
      regimeSavings: (json['regimeSavings'] as num).toDouble(),
      gaps: (json['gaps'] as List<dynamic>? ?? [])
          .map((g) => GapCard.fromStoredJson(g as Map<String, dynamic>))
          .toList(),
      totalGapAmount: totalGapAmount,
      deductionOpportunity: json['deductionOpportunity'] == null
          ? totalGapAmount
          : readInt('deductionOpportunity'),
      estimatedTaxBenefit: readInt('estimatedTaxBenefit'),
      gapCount: readInt('gapCount'),
      assumptions: (json['assumptions'] as List<dynamic>? ?? [])
          .map((item) => TaxAssumption.fromJson(item as Map<String, dynamic>))
          .toList(),
      trace: json['trace'] is Map<String, dynamic>
          ? TaxComputationTrace.fromJson(json['trace'] as Map<String, dynamic>)
          : const TaxComputationTrace(
              oldTaxBeforeCess: 0,
              newTaxBeforeCess: 0,
              oldSurcharge: 0,
              newSurcharge: 0,
              oldCess: 0,
              newCess: 0,
            ),
      confidenceScore:
          (json['confidenceScore'] as num? ?? 70).round().clamp(0, 100).toInt(),
    );
  }
}
