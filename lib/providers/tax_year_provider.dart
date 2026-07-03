import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_rule_set.dart';
import '../services/secure_storage_service.dart';

const _activeTaxYearKey = 'arth_active_tax_year';

class ActiveTaxYearNotifier extends Notifier<TaxYearId> {
  final SecureStorageService _storage = const SecureStorageService();

  @override
  TaxYearId build() {
    _loadPersistedTaxYear();
    return TaxYearId.fy2026_27;
  }

  Future<void> set(TaxYearId id) async {
    state = id;
    await _storage.write(_activeTaxYearKey, id.wireName);
  }

  Future<void> _loadPersistedTaxYear() async {
    final raw = await _storage.read(_activeTaxYearKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = TaxYearId.fromWireName(raw);
    } on FormatException {
      await _storage.delete(_activeTaxYearKey);
    }
  }
}

final activeTaxYearProvider =
    NotifierProvider<ActiveTaxYearNotifier, TaxYearId>(
  ActiveTaxYearNotifier.new,
);

final activeTaxRuleSetProvider = FutureProvider<TaxRuleSet>((ref) async {
  final taxYear = ref.watch(activeTaxYearProvider);
  return TaxRuleSet.load(taxYear);
});
