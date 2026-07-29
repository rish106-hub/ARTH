import 'dart:async';

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
    ref.listen(authProvider, (previous, next) {
      final nextUid = next?.uid;
      if (nextUid == null || nextUid.isEmpty || nextUid == _uid) return;
      _uid = nextUid;
      unawaited(_loadPersistedTaxYear());
    });
    unawaited(_loadPersistedTaxYear());
    return TaxYearId.fy2026_27;
  }

  Future<void> set(TaxYearId id) async {
    state = id;
    if (_uid == 'guest') return;
    await _storage.write(UserScopedStorageKeys.taxYear(_uid), id.wireName);
  }

  Future<void> _loadPersistedTaxYear() async {
    final key = UserScopedStorageKeys.taxYear(_uid);
    final scoped = await _storage.read(key);
    if (scoped != null && scoped.isNotEmpty) {
      try {
        if (ref.mounted) state = TaxYearId.fromWireName(scoped);
      } on FormatException {
        await _storage.delete(key);
      }
      return;
    }

    // Never migrate the legacy global key into the guest namespace. Wait until
    // authentication resolves, then move the selection into the real account.
    if (_uid == 'guest') return;

    final legacy = await _storage.read(_activeTaxYearKey);
    if (legacy == null || legacy.isEmpty) return;
    try {
      final parsed = TaxYearId.fromWireName(legacy);
      if (ref.mounted) state = parsed;
      await _storage.write(key, legacy);
      if (await _storage.read(key) == legacy) {
        await _storage.delete(_activeTaxYearKey);
      }
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
