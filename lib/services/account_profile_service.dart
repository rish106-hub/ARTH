import 'package:flutter/foundation.dart';

import '../models/account_profile.dart';
import 'auth_service.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';

class AccountProfileService {
  static const _cachePrefix = 'arth_account_profile_';

  final ServerApiService _api;
  final AuthService _auth;
  final SecureStorageService _storage;

  AccountProfileService({
    ServerApiService? api,
    AuthService? auth,
    SecureStorageService? storage,
  })  : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService(),
        _storage = storage ?? const SecureStorageService();

  Future<AccountProfile?> loadCached() async {
    final account = await _auth.loadAccount();
    final uid = account?.uid;
    if (uid == null) return null;
    final raw =
        await _storage.read('$_cachePrefix$uid', migrateFromPrefs: true);
    if (raw == null) return null;
    try {
      return AccountProfile.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<AccountProfile?> fetch() async {
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return loadCached();
      final response =
          await _api.getJson('/account/profile', bearerToken: token);
      final profile = AccountProfile.fromJson(response);
      await _persist(profile);
      return profile;
    } catch (_) {
      if (kDebugMode) debugPrint('[AccountProfileService] fetch failed');
      return loadCached();
    }
  }

  Future<AccountProfile> updateName(String name) async {
    return updateProfile(name: name);
  }

  Future<AccountProfile> updateProfile({
    String? name,
    String? phoneNumber,
    String? avatarInitials,
    String? avatarColor,
  }) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phoneNumber != null) body['phoneNumber'] = phoneNumber;
    if (avatarInitials != null) body['avatarInitials'] = avatarInitials;
    if (avatarColor != null) body['avatarColor'] = avatarColor;
    final response = await _api.patchJson(
      '/account/profile',
      bearerToken: token,
      body: body,
    );
    final current = await loadCached();
    final account = AccountProfile.fromJson(response);
    final merged = account.copyWith(pan: current?.pan ?? account.pan);
    await _persist(merged);
    return merged;
  }

  Future<PanVaultStatus> savePan({
    required String pan,
    required bool consentAccepted,
    String consentVersion = 'pan-v1',
  }) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final response = await _api.putJson(
      '/account/pan',
      bearerToken: token,
      body: {
        'pan': pan.toUpperCase(),
        'consentAccepted': consentAccepted,
        'consentVersion': consentVersion,
      },
    );
    final status = PanVaultStatus.fromJson(
      response['pan'] as Map<String, dynamic>? ?? const {'status': 'missing'},
    );
    final current = await fetch();
    if (current != null) {
      await _persist(current.copyWith(pan: status));
    }
    return status;
  }

  Future<void> deletePan() async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    await _api.delete('/account/pan', bearerToken: token);
    final current = await loadCached();
    if (current != null) {
      await _persist(current.copyWith(pan: PanVaultStatus.missing));
    }
  }

  Future<void> _persist(AccountProfile profile) async {
    await _auth.saveAccount(profile.user);
    final uid = profile.user.uid;
    if (uid != null) {
      await _storage.write('$_cachePrefix$uid', profile.toJsonString());
    }
  }
}
