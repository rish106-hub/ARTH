import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SecureStorageWriteObserver = void Function(
  String key,
  String? value,
  DateTime updatedAt,
);

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'arth_secure'),
    iOptions: IOSOptions(
      accountName: 'arth_secure',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accountName: 'arth_secure',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static SecureStorageWriteObserver? writeObserver;
  static final Map<String, Future<void>> _keyOperations = {};
  static DateTime? _serverTimeAtSync;
  static Stopwatch? _serverClock;

  const SecureStorageService();

  static void observeServerTime(DateTime serverTime) {
    _serverTimeAtSync = serverTime.toUtc();
    _serverClock = Stopwatch()..start();
  }

  static void resetServerClockForTests() {
    _serverTimeAtSync = null;
    _serverClock = null;
  }

  Future<String?> read(String key, {bool migrateFromPrefs = false}) async {
    await _keyOperations[key];
    final secureValue = await _readSecure(key);
    if (secureValue != null || !migrateFromPrefs) {
      return secureValue;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key) ?? prefs.getBool(key)?.toString();
    if (legacyValue == null) return null;

    await write(key, legacyValue);
    await prefs.remove(key);
    return legacyValue;
  }

  Future<void> write(String key, String value) => _serialize(key, () async {
        final updatedAt = await _nextTimestamp(key);
        try {
          await _storage.write(key: key, value: value);
          await _storage.write(
            key: _updatedAtKey(key),
            value: updatedAt.toIso8601String(),
          );
        } catch (_) {
          // Existing provider flows are local-first and must not crash when a
          // platform storage plugin is unavailable. The observer still mirrors
          // the value to the authenticated server backup when possible.
        }
        writeObserver?.call(key, value, updatedAt);
      });

  Future<DateTime?> updatedAt(String key) async {
    await _keyOperations[key];
    final raw = await _readSecure(_updatedAtKey(key));
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> writeRestored(
    String key,
    String value,
    DateTime updatedAt,
  ) =>
      _serialize(key, () async {
        await _storage.write(key: key, value: value);
        await _storage.write(
          key: _updatedAtKey(key),
          value: updatedAt.toUtc().toIso8601String(),
        );
      });

  Future<void> deleteRestored(String key, DateTime updatedAt) =>
      _serialize(key, () async {
        await _storage.delete(key: key);
        await _storage.write(
          key: _updatedAtKey(key),
          value: updatedAt.toUtc().toIso8601String(),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      });

  Future<void> delete(String key) => _serialize(key, () async {
        final deletedAt = await _nextTimestamp(key);
        try {
          await _storage.delete(key: key);
          await _storage.write(
            key: _updatedAtKey(key),
            value: deletedAt.toIso8601String(),
          );
        } catch (_) {}
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        } catch (_) {}
        writeObserver?.call(key, null, deletedAt);
      });

  Future<bool> reconcileTimestamp({
    required String key,
    required String? expectedValue,
    required DateTime expectedUpdatedAt,
    required DateTime acceptedUpdatedAt,
  }) =>
      _serialize(key, () async {
        final currentValue = await _readSecure(key);
        final currentTimestamp = DateTime.tryParse(
          await _readSecure(_updatedAtKey(key)) ?? '',
        )?.toUtc();
        if (currentValue != expectedValue ||
            currentTimestamp != expectedUpdatedAt.toUtc()) {
          return false;
        }
        await _storage.write(
          key: _updatedAtKey(key),
          value: acceptedUpdatedAt.toUtc().toIso8601String(),
        );
        return true;
      });

  String _updatedAtKey(String key) => '$key.__updated_at';

  Future<String?> _readSecure(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  Future<DateTime> _nextTimestamp(String key) async {
    final previous = DateTime.tryParse(
      await _readSecure(_updatedAtKey(key)) ?? '',
    )?.toUtc();
    var next = _estimatedServerNow();
    if (previous != null && !next.isAfter(previous)) {
      next = previous.add(const Duration(microseconds: 1));
    }
    return next;
  }

  DateTime _estimatedServerNow() {
    final serverTime = _serverTimeAtSync;
    final clock = _serverClock;
    if (serverTime == null || clock == null) return DateTime.now().toUtc();
    return serverTime.add(clock.elapsed);
  }

  Future<T> _serialize<T>(
    String key,
    Future<T> Function() operation,
  ) {
    final previous = _keyOperations[key] ?? Future<void>.value();
    final completer = Completer<T>();

    Future<void> execute() async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    late final Future<void> current;
    current =
        previous.catchError((_) {}).then((_) => execute()).whenComplete(() {
      if (identical(_keyOperations[key], current)) {
        _keyOperations.remove(key);
      }
    });
    _keyOperations[key] = current;
    return completer.future;
  }
}
