import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';
import 'user_scoped_storage.dart';

class DurableUserStateService {
  static const maxPayloadBytes = 16 * 1024 * 1024;
  static const _debounceDelay = Duration(milliseconds: 300);
  static const _maxDebounceWait = Duration(seconds: 3);

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
  DateTime? _firstQueuedAt;
  bool _flushInProgress = false;
  int _retryAttempt = 0;

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
    if (!UserScopedStorageKeys.isDurableKey(key)) return;
    if (value != null && _isOversized(value)) {
      _pending.remove(key);
      unawaited(_recordOversizedBackup(key));
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
    _retryAttempt = 0;
    _firstQueuedAt ??= DateTime.now();
    final remaining =
        _maxDebounceWait - DateTime.now().difference(_firstQueuedAt!);
    _flushTimer?.cancel();
    if (remaining <= Duration.zero) {
      _flushTimer = null;
      unawaited(flushScheduled());
      return;
    }
    _flushTimer = Timer(
      remaining < _debounceDelay ? remaining : _debounceDelay,
      () => unawaited(flushScheduled()),
    );
  }

  Future<void> flushScheduled() async {
    if (_flushInProgress) return;
    _flushInProgress = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    _firstQueuedAt = null;
    var hadFailure = false;
    try {
      if (_pending.isEmpty) return;

      final session = await _auth.getValidSession();
      if (session == null) {
        hadFailure = true;
        return;
      }
      final uid = session.uid;
      final token = session.accessToken;

      final pending = Map<String, _PendingWrite>.from(_pending);
      _pending.clear();
      for (final entry in pending.entries) {
        final namespace = UserScopedStorageKeys.durableNamespaceForKey(
          uid,
          entry.key,
        );
        if (namespace == null) continue;
        final succeeded = entry.value.value == null
            ? await _delete(
                token: token,
                namespace: namespace,
                key: entry.key,
                updatedAt: entry.value.updatedAt,
              )
            : await _push(
                token: token,
                namespace: namespace,
                key: entry.key,
                value: entry.value.value!,
                updatedAt: entry.value.updatedAt,
              );
        if (!succeeded) {
          hadFailure = true;
          _requeue(entry.key, entry.value);
        }
      }
    } finally {
      _flushInProgress = false;
      if (_pending.isNotEmpty && _flushTimer == null) {
        if (hadFailure) {
          _scheduleRetry();
        } else {
          _firstQueuedAt = DateTime.now();
          _flushTimer = Timer(
            _debounceDelay,
            () => unawaited(flushScheduled()),
          );
        }
      } else if (!hadFailure) {
        _retryAttempt = 0;
      }
    }
  }

  /// Restores missing or newer server state before account-scoped providers
  /// load. Existing device data wins when it has the same or a newer timestamp.
  Future<void> restore(String uid) async {
    if (uid.isEmpty) return;
    final session = await _auth.getValidSession();
    if (session == null || session.uid != uid) return;
    final token = session.accessToken;

    try {
      final response = await _api.getJson('/user-state', bearerToken: token);
      final serverTime = _observeServerTime(response);
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
            serverTime: serverTime,
          );
        } catch (_) {
          if (kDebugMode) {
            debugPrint(
              '[DurableUserState] restore deferred: ${entry.key}',
            );
          }
        }
      }
      if (_pending.isNotEmpty && _flushTimer == null) {
        _scheduleRetry();
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
    required DateTime? serverTime,
  }) async {
    final localValue = await _storage.read(key, migrateFromPrefs: true);
    var localUpdatedAt = await _storage.updatedAt(key);
    if (localUpdatedAt != null &&
        serverTime != null &&
        localUpdatedAt.isAfter(serverTime.add(const Duration(minutes: 5)))) {
      final reconciled = await _storage.reconcileTimestamp(
        key: key,
        expectedValue: localValue,
        expectedUpdatedAt: localUpdatedAt,
        acceptedUpdatedAt: serverTime,
      );
      if (reconciled) localUpdatedAt = serverTime;
    }

    if (remote == null) {
      if (localValue != null) {
        final updatedAt = localUpdatedAt ?? DateTime.now().toUtc();
        if (localUpdatedAt == null) {
          await _storage.writeRestored(key, localValue, updatedAt);
        }
        final succeeded = await _push(
          token: token,
          namespace: namespace,
          key: key,
          value: localValue,
          updatedAt: updatedAt,
        );
        if (!succeeded) {
          _requeue(key, _PendingWrite(value: localValue, updatedAt: updatedAt));
        }
      } else if (localUpdatedAt != null) {
        final succeeded = await _delete(
          token: token,
          namespace: namespace,
          key: key,
          updatedAt: localUpdatedAt,
        );
        if (!succeeded) {
          _requeue(key, _PendingWrite(value: null, updatedAt: localUpdatedAt));
        }
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
      final succeeded = await _delete(
        token: token,
        namespace: namespace,
        key: key,
        updatedAt: localUpdatedAt,
      );
      if (!succeeded) {
        _requeue(key, _PendingWrite(value: null, updatedAt: localUpdatedAt));
      }
    } else {
      final succeeded = await _push(
        token: token,
        namespace: namespace,
        key: key,
        value: localValue,
        updatedAt: localUpdatedAt,
      );
      if (!succeeded) {
        _requeue(
          key,
          _PendingWrite(value: localValue, updatedAt: localUpdatedAt),
        );
      }
    }
  }

  void _dropPendingThrough(String key, DateTime remoteUpdatedAt) {
    final pending = _pending[key];
    if (pending != null && !pending.updatedAt.isAfter(remoteUpdatedAt)) {
      _pending.remove(key);
    }
  }

  Future<bool> _push({
    required String token,
    required String namespace,
    required String key,
    required String value,
    required DateTime updatedAt,
  }) async {
    if (_isOversized(value)) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] backup too large: $namespace');
      }
      return true;
    }
    try {
      final response = await _api.putJson(
        '/user-state/$namespace',
        bearerToken: token,
        body: {
          'payload': value,
          'clientUpdatedAt': updatedAt.toIso8601String(),
        },
      );
      _observeServerTime(response);
      final item = response['item'];
      if (item is! Map) return true;
      final acceptedAt = DateTime.tryParse(
        item['clientUpdatedAt']?.toString() ?? '',
      )?.toUtc();
      if (acceptedAt == null) return true;
      final acceptedValue =
          item['deleted'] == true ? null : item['payload']?.toString();
      if (acceptedValue == value) {
        await _storage.reconcileTimestamp(
          key: key,
          expectedValue: value,
          expectedUpdatedAt: updatedAt,
          acceptedUpdatedAt: acceptedAt,
        );
      } else if (acceptedAt.isAfter(updatedAt)) {
        _dropPendingThrough(key, acceptedAt);
        if (item['deleted'] == true) {
          await _storage.deleteRestored(key, acceptedAt);
        } else if (acceptedValue != null) {
          await _storage.writeRestored(key, acceptedValue, acceptedAt);
        }
      }
      return true;
    } catch (_) {
      // The local copy remains authoritative and is retried at next hydration
      // or after the next write.
      if (kDebugMode) {
        debugPrint('[DurableUserState] backup deferred: $namespace');
      }
      return false;
    }
  }

  bool _isOversized(String value) {
    if (value.length > maxPayloadBytes) return true;
    return utf8.encode(value).length > maxPayloadBytes;
  }

  Future<bool> _delete({
    required String token,
    required String namespace,
    required String key,
    required DateTime updatedAt,
  }) async {
    try {
      final response = await _api.deleteJson(
        '/user-state/$namespace',
        bearerToken: token,
        body: {'clientUpdatedAt': updatedAt.toIso8601String()},
      );
      _observeServerTime(response);
      final item = response['item'];
      if (item is! Map) return true;
      final acceptedAt = DateTime.tryParse(
        item['clientUpdatedAt']?.toString() ?? '',
      )?.toUtc();
      if (acceptedAt == null) return true;
      if (item['deleted'] == true) {
        await _storage.reconcileTimestamp(
          key: key,
          expectedValue: null,
          expectedUpdatedAt: updatedAt,
          acceptedUpdatedAt: acceptedAt,
        );
      } else if (acceptedAt.isAfter(updatedAt)) {
        final acceptedValue = item['payload']?.toString();
        if (acceptedValue != null) {
          _dropPendingThrough(key, acceptedAt);
          await _storage.writeRestored(key, acceptedValue, acceptedAt);
        }
      }
      return true;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[DurableUserState] delete deferred: $namespace');
      }
      return false;
    }
  }

  void _requeue(String key, _PendingWrite failed) {
    final current = _pending[key];
    if (current == null || current.updatedAt.isBefore(failed.updatedAt)) {
      _pending[key] = failed;
    }
  }

  void _scheduleRetry() {
    _flushTimer?.cancel();
    final exponent = _retryAttempt.clamp(0, 6);
    final delay = Duration(seconds: 5 * (1 << exponent));
    _retryAttempt += 1;
    _firstQueuedAt = DateTime.now();
    _flushTimer = Timer(delay, () => unawaited(flushScheduled()));
  }

  Future<void> _recordOversizedBackup(String key) {
    return _storage.write(
      'arth_durable_backup_oversized',
      jsonEncode({
        'key': key,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  DateTime? _observeServerTime(Map<String, dynamic> response) {
    final serverTime = DateTime.tryParse(
      response['serverTime']?.toString() ?? '',
    )?.toUtc();
    if (serverTime != null) {
      SecureStorageService.observeServerTime(serverTime);
    }
    return serverTime;
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
