import 'gap_card.dart';

enum TaxRegime { newRegime, oldRegime }

class TaxResult {
  final double oldRegimeTax;
  final double newRegimeTax;
  final double oldRegimeTaxableIncome;
  final double newRegimeTaxableIncome;
  final double totalDeductionsOld;
  final TaxRegime betterRegime;
  final double regimeSavings; // |old - new|
  final List<GapCard> gaps;
  final int totalGapAmount;
  final int gapCount;

  const TaxResult({
    required this.oldRegimeTax,
    required this.newRegimeTax,
    required this.oldRegimeTaxableIncome,
    required this.newRegimeTaxableIncome,
    required this.totalDeductionsOld,
    required this.betterRegime,
    required this.regimeSavings,
    required this.gaps,
    required this.totalGapAmount,
    required this.gapCount,
  });

  bool get isOldBetter => betterRegime == TaxRegime.oldRegime;

  double get currentTax =>
      betterRegime == TaxRegime.oldRegime ? oldRegimeTax : newRegimeTax;

  double get worseTax =>
      betterRegime == TaxRegime.oldRegime ? newRegimeTax : oldRegimeTax;

  String get betterRegimeLabel =>
      betterRegime == TaxRegime.oldRegime ? 'Old Regime' : 'New Regime';

  String get worseRegimeLabel =>
      betterRegime == TaxRegime.oldRegime ? 'New Regime' : 'Old Regime';

  Map<String, dynamic> toJson() => {
        'oldRegimeTax': oldRegimeTax,
        'newRegimeTax': newRegimeTax,
        'oldRegimeTaxableIncome': oldRegimeTaxableIncome,
        'newRegimeTaxableIncome': newRegimeTaxableIncome,
        'totalDeductionsOld': totalDeductionsOld,
        'betterRegime': betterRegime.name,
        'regimeSavings': regimeSavings,
        'gaps': gaps.map((g) => g.toJson()).toList(),
        'totalGapAmount': totalGapAmount,
        'gapCount': gapCount,
      };

  factory TaxResult.fromJson(Map<String, dynamic> json) {
    final betterRegimeName = json['betterRegime'] as String? ?? 'newRegime';
    return TaxResult(
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
      totalGapAmount: json['totalGapAmount'] as int? ?? 0,
      gapCount: json['gapCount'] as int? ?? 0,
    );
  }
}
