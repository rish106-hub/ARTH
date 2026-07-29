import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_rule_set.dart';
import '../services/secure_storage_service.dart';
import '../services/user_scoped_storage.dart';
import 'auth_provider.dart';

const _activeTaxYearKey = 'arth_active_tax_year';

class ActiveTaxYearNotifier extends Notifier<TaxYearId> {
  final SecureStorageService _storage = const SecureStorageService();
  late String _uid;

  @override
  TaxYearId build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    _loadPersistedTaxYear();
    return TaxYearId.fy2026_27;
  }

  Future<void> set(TaxYearId id) async {
    state = id;
    await _storage.write(UserScopedStorageKeys.taxYear(_uid), id.wireName);
  }

  Future<void> _loadPersistedTaxYear() async {
    final key = UserScopedStorageKeys.taxYear(_uid);
    final scoped = await _storage.read(key);
    final raw = scoped ?? await _storage.read(_activeTaxYearKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = TaxYearId.fromWireName(raw);
      if (scoped == null) {
        await _storage.write(key, raw);
        if (await _storage.read(key) == raw) {
          await _storage.delete(_activeTaxYearKey);
        }
      }
    } on FormatException {
      await _storage.delete(scoped == null ? _activeTaxYearKey : key);
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
