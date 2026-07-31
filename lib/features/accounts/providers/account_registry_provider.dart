import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/spend_map.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../engine/account_inference.dart';
import '../models/owned_account.dart';

/// The user's accounts, learned from their SMS and refined by their answers.
class AccountRegistryNotifier extends Notifier<AccountRegistry> {
  final _storage = const SecureStorageService();
  final _inference = const AccountInference();
  late String _uid;

  /// Guards against a load landing after a mutation and clobbering it, the same
  /// way the other user-state notifiers do.
  int _mutationRevision = 0;

  @override
  AccountRegistry build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const AccountRegistry.empty();
  }

  Future<void> _load(String uid) async {
    final revisionAtStart = _mutationRevision;
    final raw = await _storage.read(UserScopedStorageKeys.ownedAccounts(uid));
    if (raw == null ||
        !ref.mounted ||
        uid != _uid ||
        revisionAtStart != _mutationRevision) {
      return;
    }
    state = AccountRegistry.fromJsonString(raw);
  }

  Future<void> _persist() async {
    _mutationRevision++;
    await _storage.write(
      UserScopedStorageKeys.ownedAccounts(_uid),
      state.toJsonString(),
    );
  }

  /// Folds the endpoints seen in a scan into the registry. Called after every
  /// scan; answers the user already gave are preserved.
  Future<void> observe(Iterable<FinanceTxn> txns) async {
    final updated = _inference.learn(txns, state);
    if (updated.length == state.length &&
        updated.pendingConfirmation.length ==
            state.pendingConfirmation.length) {
      // Nothing new to show or store.
      return;
    }
    state = updated;
    await _persist();
  }

  Future<void> confirm(String id) =>
      _setOwnership(id, AccountOwnership.confirmed);

  Future<void> reject(String id) =>
      _setOwnership(id, AccountOwnership.rejected);

  Future<void> _setOwnership(String id, AccountOwnership ownership) async {
    final updated = state.withOwnership(id, ownership);
    if (updated.accounts[id]?.ownership == state.accounts[id]?.ownership) {
      return;
    }
    state = updated;
    await _persist();
  }

  Future<void> rename(String id, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    state = state.withLabel(id, trimmed);
    await _persist();
  }

  /// True when [endpoint] belongs to the user. The correlator asks this to decide
  /// whether a movement is internal.
  bool owns(TxnEndpoint? endpoint) => state.owns(endpoint);

  Future<void> clearLocalData() async {
    _mutationRevision++;
    state = const AccountRegistry.empty();
    await _storage.delete(UserScopedStorageKeys.ownedAccounts(_uid));
  }
}

final accountRegistryProvider =
    NotifierProvider<AccountRegistryNotifier, AccountRegistry>(
  AccountRegistryNotifier.new,
);
