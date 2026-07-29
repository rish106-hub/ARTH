import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';
import 'user_scoped_storage.dart';

class DurableUserStateService {
  static const maxPayloadBytes = 16 * 1024 * 1024;
  static const _maxClockLead = Duration(minutes: 5);

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
  final Map<String, DateTime> _writeFloors = {};
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
    final proposedAt = (updatedAt ?? DateTime.now()).toUtc();
    final existing = _pending[key];
    if (existing != null && existing.updatedAt.isAfter(proposedAt)) {
      return;
    }
    final normalizedUpdatedAt = _coalesceLocalTimestamp(key, proposedAt);
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

    final session = await _loadBoundSession();
    if (session == null) return;

    final pending = Map<String, _PendingWrite>.from(_pending);
    _pending.clear();
    for (final entry in pending.entries) {
      final namespace = UserScopedStorageKeys.durableNamespaceForKey(
        session.uid,
        entry.key,
      );
      if (namespace == null) continue;
      if (entry.value.value == null) {
        await _delete(
          session: session,
          namespace: namespace,
          storageKey: entry.key,
          updatedAt: entry.value.updatedAt,
        );
      } else {
        await _push(
          session: session,
          namespace: namespace,
          storageKey: entry.key,
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
    final session = await _loadBoundSession(expectedUid: uid);
    if (session == null) return;

    try {
      final response =
          await _api.getJson('/user-state', bearerToken: session.token);
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
            session: session,
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
    required _AuthSession session,
    required String namespace,
    required String key,
    required Map<String, dynamic>? remote,
  }) async {
    final localValue = await _storage.read(key, migrateFromPrefs: true);
    final localUpdatedAt = await _storage.updatedAt(key);

    if (remote == null) {
      if (localValue != null) {
        final updatedAt = _coalesceLocalTimestamp(
          key,
          localUpdatedAt ?? DateTime.now().toUtc(),
        );
        if (localUpdatedAt == null) {
          await _storage.writeRestored(key, localValue, updatedAt);
        }
        await _push(
          session: session,
          namespace: namespace,
          storageKey: key,
          value: localValue,
          updatedAt: updatedAt,
        );
      } else if (localUpdatedAt != null) {
        await _delete(
          session: session,
          namespace: namespace,
          storageKey: key,
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
    _rememberServerTimestamp(key, remoteUpdatedAt);

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
        session: session,
        namespace: namespace,
        storageKey: key,
        updatedAt: localUpdatedAt,
      );
    } else {
      await _push(
        session: session,
        namespace: namespace,
        storageKey: key,
        value: localValue,
        updatedAt: localUpdatedAt,
      );
    }
  }

  Future<_AuthSession?> _loadBoundSession({String? expectedUid}) async {
    final account = await _auth.loadAccount();
    final uid = account?.uid;
    final token = await _auth.getValidAccessToken();
    if (uid == null || uid.isEmpty || token == null) return null;
    final tokenUid = _auth.userIdFromAccessToken(token);
    if (tokenUid == null || tokenUid != uid) return null;
    if (expectedUid != null && expectedUid != uid) return null;
    return _AuthSession(uid: uid, token: token);
  }

  DateTime _coalesceLocalTimestamp(String key, DateTime proposed) {
    var normalized = proposed.toUtc();
    final floor = _writeFloors[key];
    if (floor != null && !normalized.isAfter(floor)) {
      normalized = floor.add(const Duration(milliseconds: 1));
    }
    _writeFloors[key] = normalized;
    return normalized;
  }

  DateTime _clampFutureLead(DateTime proposed) {
    final now = DateTime.now().toUtc();
    final normalized = proposed.toUtc();
    if (normalized.isAfter(now.add(_maxClockLead))) {
      return now;
    }
    return normalized;
  }

  void _rememberServerTimestamp(String key, DateTime serverAt) {
    final existing = _writeFloors[key];
    if (existing == null || serverAt.isAfter(existing)) {
      _writeFloors[key] = serverAt.toUtc();
    }
  }

  void _dropPendingThrough(String key, DateTime remoteUpdatedAt) {
    final pending = _pending[key];
    if (pending != null && !pending.updatedAt.isAfter(remoteUpdatedAt)) {
      _pending.remove(key);
    }
  }

  Future<void> _push({
    required _AuthSession session,
    required String namespace,
    required String storageKey,
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
      final serverUpdatedAt = _clampFutureLead(updatedAt);
      final response = await _api.putJson(
        '/user-state/$namespace',
        bearerToken: session.token,
        body: {
          'payload': value,
          'clientUpdatedAt': serverUpdatedAt.toIso8601String(),
        },
      );
      final item = response['item'];
      if (item is Map) {
        final serverAt = DateTime.tryParse(
          item['clientUpdatedAt']?.toString() ?? '',
        )?.toUtc();
        if (serverAt != null) {
          _rememberServerTimestamp(storageKey, serverAt);
          if (!serverAt.isAtSameMomentAs(serverUpdatedAt)) {
            await _storage.writeRestored(storageKey, value, serverAt);
          }
        }
      }
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
    required _AuthSession session,
    required String namespace,
    required String storageKey,
    required DateTime updatedAt,
  }) async {
    try {
      final serverUpdatedAt = _clampFutureLead(updatedAt);
      await _api.delete(
        '/user-state/$namespace',
        bearerToken: session.token,
        body: {'clientUpdatedAt': serverUpdatedAt.toIso8601String()},
      );
      _rememberServerTimestamp(storageKey, serverUpdatedAt);
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

class _AuthSession {
  const _AuthSession({
    required this.uid,
    required this.token,
  });

  final String uid;
  final String token;
}

final durableUserStateService = DurableUserStateService();
