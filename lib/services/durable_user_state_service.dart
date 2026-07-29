import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';
import 'user_scoped_storage.dart';

class DurableUserStateService {
  DurableUserStateService({
    AuthService? auth,
    ServerApiService? api,
    SecureStorageService? storage,
  })  : _auth = auth ?? AuthService(),
        _api = api ?? ServerApiService(),
        _storage = storage ?? const SecureStorageService();

  final AuthService _auth;
  final ServerApiService _api;
  final SecureStorageService _storage;
  final Map<String, String?> _pending = {};
  Timer? _flushTimer;

  void registerWriteObserver() {
    SecureStorageService.writeObserver = scheduleBackup;
  }

  void scheduleBackup(String key, String? value) {
    _pending[key] = value;
    _flushTimer?.cancel();
    _flushTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(flushScheduled()),
    );
  }

  Future<void> flushScheduled() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;

    final account = await _auth.loadAccount();
    final uid = account?.uid;
    final token = await _auth.getValidAccessToken();
    if (uid == null || uid.isEmpty || token == null) return;

    final pending = Map<String, String?>.from(_pending);
    _pending.clear();
    for (final entry in pending.entries) {
      final namespace = UserScopedStorageKeys.durableNamespaceForKey(
        uid,
        entry.key,
      );
      if (namespace == null) continue;
      if (entry.value == null) {
        await _delete(
          token: token,
          namespace: namespace,
          key: entry.key,
        );
      } else {
        await _push(
          token: token,
          namespace: namespace,
          key: entry.key,
          value: entry.value!,
        );
      }
    }
  }

  /// Restores missing or newer server state before account-scoped providers
  /// load. Existing device data wins when it has the same or a newer timestamp.
  Future<void> restore(String uid) async {
    if (uid.isEmpty) return;
    final token = await _auth.getValidAccessToken();
    if (token == null) return;

    try {
      final response = await _api.getJson('/user-state', bearerToken: token);
      final remoteByNamespace = <String, Map<String, dynamic>>{};
      for (final raw in response['items'] as List<dynamic>? ?? const []) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final namespace = item['namespace']?.toString();
        if (namespace != null) remoteByNamespace[namespace] = item;
      }

      for (final entry in UserScopedStorageKeys.durableForUser(uid).entries) {
        final namespace = entry.key;
        final key = entry.value;
        final localValue = await _storage.read(key, migrateFromPrefs: true);
        final localUpdatedAt = await _storage.updatedAt(key);
        final remote = remoteByNamespace[namespace];

        if (remote == null) {
          if (localValue != null) {
            await _push(
              token: token,
              namespace: namespace,
              key: key,
              value: localValue,
            );
          } else if (localUpdatedAt != null) {
            await _delete(
              token: token,
              namespace: namespace,
              key: key,
            );
          }
          continue;
        }

        final remoteDeleted = remote['deleted'] == true;
        final remoteValue = remote['payload']?.toString();
        final remoteUpdatedAt = DateTime.tryParse(
          remote['clientUpdatedAt']?.toString() ?? '',
        )?.toUtc();
        if (remoteUpdatedAt == null) continue;

        if (localValue == null) {
          if (localUpdatedAt == null ||
              remoteUpdatedAt.isAfter(localUpdatedAt)) {
            if (remoteDeleted) {
              await _storage.deleteRestored(key, remoteUpdatedAt);
            } else if (remoteValue != null) {
              await _storage.writeRestored(key, remoteValue, remoteUpdatedAt);
            }
          } else if (!remoteDeleted) {
            await _delete(
              token: token,
              namespace: namespace,
              key: key,
            );
          }
          continue;
        }

        // Old app versions did not write timestamps. Preserve that existing
        // device data and seed the server instead of replacing it.
        if (localUpdatedAt == null ||
            !remoteUpdatedAt.isAfter(localUpdatedAt)) {
          await _push(
            token: token,
            namespace: namespace,
            key: key,
            value: localValue,
          );
          continue;
        }

        if (remoteDeleted) {
          await _storage.deleteRestored(key, remoteUpdatedAt);
        } else if (remoteValue != null) {
          await _storage.writeRestored(key, remoteValue, remoteUpdatedAt);
        }
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] restore deferred until online');
      }
    }
  }

  Future<void> _push({
    required String token,
    required String namespace,
    required String key,
    required String value,
  }) async {
    try {
      final updatedAt = await _storage.updatedAt(key) ?? DateTime.now().toUtc();
      await _api.putJson(
        '/user-state/$namespace',
        bearerToken: token,
        body: {
          'payload': value,
          'clientUpdatedAt': updatedAt.toIso8601String(),
        },
      );
    } catch (_) {
      // The local copy remains authoritative and is retried at next hydration
      // or after the next write.
      if (kDebugMode) {
        debugPrint('[DurableUserState] backup deferred: $namespace');
      }
    }
  }

  Future<void> _delete({
    required String token,
    required String namespace,
    required String key,
  }) async {
    try {
      final updatedAt = await _storage.updatedAt(key) ?? DateTime.now().toUtc();
      await _api.delete(
        '/user-state/$namespace',
        bearerToken: token,
        body: {'clientUpdatedAt': updatedAt.toIso8601String()},
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] delete deferred: $namespace');
      }
    }
  }
}

final durableUserStateService = DurableUserStateService();
