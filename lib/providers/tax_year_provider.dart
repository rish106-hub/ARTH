import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_rule_set.dart';

class ActiveTaxYearNotifier extends Notifier<TaxYearId> {
  @override
  TaxYearId build() => TaxYearId.fy2026_27;

  void set(TaxYearId id) => state = id;
}

final activeTaxYearProvider =
    NotifierProvider<ActiveTaxYearNotifier, TaxYearId>(
  ActiveTaxYearNotifier.new,
);

final activeTaxRuleSetProvider = FutureProvider<TaxRuleSet>((ref) async {
  final taxYear = ref.watch(activeTaxYearProvider);
  return TaxRuleSet.load(taxYear);
});
