import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account_profile.dart';
import '../services/account_profile_service.dart';

final accountProfileServiceProvider = Provider<AccountProfileService>(
  (ref) => AccountProfileService(),
);

class AccountProfileNotifier extends AsyncNotifier<AccountProfile?> {
  late final AccountProfileService _service;

  @override
  Future<AccountProfile?> build() async {
    _service = ref.read(accountProfileServiceProvider);
    final cached = await _service.loadCached();
    final remote = await _service.fetch();
    return remote ?? cached;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.fetch);
  }

  Future<void> updateName(String name) async {
    await updateProfile(name: name);
  }

  Future<void> updateProfile({
    String? name,
    String? phoneNumber,
    String? avatarInitials,
    String? avatarColor,
  }) async {
    final previous = state.asData?.value;
    state = const AsyncLoading();
    try {
      final updated = await _service.updateProfile(
        name: name,
        phoneNumber: phoneNumber,
        avatarInitials: avatarInitials,
        avatarColor: avatarColor,
      );
      state = AsyncData(updated);
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> savePan(String pan) async {
    final current = state.asData?.value;
    if (current == null) throw StateError('account unavailable');
    state = AsyncData(current);
    final status = await _service.savePan(
      pan: pan,
      consentAccepted: true,
    );
    state = AsyncData(current.copyWith(pan: status));
  }

  Future<void> deletePan() async {
    final current = state.asData?.value;
    if (current == null) return;
    await _service.deletePan();
    state = AsyncData(current.copyWith(pan: PanVaultStatus.missing));
  }

  Future<void> clearLocalOnly() async {
    await _service.clearCachedForCurrentUser();
    state = const AsyncData(null);
  }
}

final accountProfileProvider =
    AsyncNotifierProvider<AccountProfileNotifier, AccountProfile?>(
  AccountProfileNotifier.new,
);
