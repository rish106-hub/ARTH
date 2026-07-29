import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';
import 'user_scoped_storage.dart';

class DurableUserStateService {
  static const maxPayloadBytes = 16 * 1024 * 1024;

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
  final Map<String, _PendingWrite> _pending = {};
  Timer? _flushTimer;

  void registerWriteObserver() {
    SecureStorageService.writeObserver = (key, value, updatedAt) {
      scheduleBackup(key, value, updatedAt);
    };
  }

  void scheduleBackup(
    String key,
    String? value, [
    DateTime? updatedAt,
  ]) {
    if (value != null && _isOversized(value)) {
      _pending.remove(key);
      if (kDebugMode) {
        debugPrint('[DurableUserState] backup too large: $key');
      }
      return;
    }
    final normalizedUpdatedAt = (updatedAt ?? DateTime.now()).toUtc();
    final existing = _pending[key];
    if (existing != null && existing.updatedAt.isAfter(normalizedUpdatedAt)) {
      return;
    }
    _pending[key] = _PendingWrite(
      value: value,
      updatedAt: normalizedUpdatedAt,
    );
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

    final pending = Map<String, _PendingWrite>.from(_pending);
    _pending.clear();
    for (final entry in pending.entries) {
      final namespace = UserScopedStorageKeys.durableNamespaceForKey(
        uid,
        entry.key,
      );
      if (namespace == null) continue;
      if (entry.value.value == null) {
        await _delete(
          token: token,
          namespace: namespace,
          updatedAt: entry.value.updatedAt,
        );
      } else {
        await _push(
          token: token,
          namespace: namespace,
          value: entry.value.value!,
          updatedAt: entry.value.updatedAt,
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
        try {
          await _restoreNamespace(
            token: token,
            namespace: entry.key,
            key: entry.value,
            remote: remoteByNamespace[entry.key],
          );
        } catch (_) {
          if (kDebugMode) {
            debugPrint(
              '[DurableUserState] restore deferred: ${entry.key}',
            );
          }
        }
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] restore deferred until online');
      }
    }
  }

  Future<void> _restoreNamespace({
    required String token,
    required String namespace,
    required String key,
    required Map<String, dynamic>? remote,
  }) async {
    final localValue = await _storage.read(key, migrateFromPrefs: true);
    final localUpdatedAt = await _storage.updatedAt(key);

    if (remote == null) {
      if (localValue != null) {
        final updatedAt = localUpdatedAt ?? DateTime.now().toUtc();
        if (localUpdatedAt == null) {
          await _storage.writeRestored(key, localValue, updatedAt);
        }
        await _push(
          token: token,
          namespace: namespace,
          value: localValue,
          updatedAt: updatedAt,
        );
      } else if (localUpdatedAt != null) {
        await _delete(
          token: token,
          namespace: namespace,
          updatedAt: localUpdatedAt,
        );
      }
      return;
    }

    final remoteDeleted = remote['deleted'] == true;
    final remoteValue = remote['payload']?.toString();
    final remoteUpdatedAt = DateTime.tryParse(
      remote['clientUpdatedAt']?.toString() ?? '',
    )?.toUtc();
    if (remoteUpdatedAt == null) return;

    if (localUpdatedAt == null || remoteUpdatedAt.isAfter(localUpdatedAt)) {
      _dropPendingThrough(key, remoteUpdatedAt);
      if (remoteDeleted) {
        await _storage.deleteRestored(key, remoteUpdatedAt);
      } else if (remoteValue != null) {
        await _storage.writeRestored(key, remoteValue, remoteUpdatedAt);
      }
      return;
    }

    if (localValue == null) {
      await _delete(
        token: token,
        namespace: namespace,
        updatedAt: localUpdatedAt,
      );
    } else {
      await _push(
        token: token,
        namespace: namespace,
        value: localValue,
        updatedAt: localUpdatedAt,
      );
    }
  }

  void _dropPendingThrough(String key, DateTime remoteUpdatedAt) {
    final pending = _pending[key];
    if (pending != null && !pending.updatedAt.isAfter(remoteUpdatedAt)) {
      _pending.remove(key);
    }
  }

  Future<void> _push({
    required String token,
    required String namespace,
    required String value,
    required DateTime updatedAt,
  }) async {
    if (_isOversized(value)) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] backup too large: $namespace');
      }
      return;
    }
    try {
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

  bool _isOversized(String value) {
    if (value.length > maxPayloadBytes) return true;
    return utf8.encode(value).length > maxPayloadBytes;
  }

  Future<void> _delete({
    required String token,
    required String namespace,
    required DateTime updatedAt,
  }) async {
    try {
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

class _PendingWrite {
  const _PendingWrite({
    required this.value,
    required this.updatedAt,
  });

  final String? value;
  final DateTime updatedAt;
}

final durableUserStateService = DurableUserStateService();
