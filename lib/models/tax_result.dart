import 'gap_card.dart';

enum TaxRegime { newRegime, oldRegime }

class TaxResult {
  final double oldRegimeTax;
  final double newRegimeTax;
  final double oldRegimeTaxableIncome;
  final double newRegimeTaxableIncome;
  final double totalDeductionsOld;
  final TaxRegime betterRegime;
  final double regimeSavings;  // |old - new|
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
}
