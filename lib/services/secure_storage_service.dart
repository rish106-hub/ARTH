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

  const SecureStorageService();

  Future<String?> read(String key, {bool migrateFromPrefs = false}) async {
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

  Future<void> write(String key, String value) async {
    final updatedAt = DateTime.now().toUtc();
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
  }

  Future<DateTime?> updatedAt(String key) async {
    final raw = await _readSecure(_updatedAtKey(key));
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> writeRestored(
    String key,
    String value,
    DateTime updatedAt,
  ) async {
    await _storage.write(key: key, value: value);
    await _storage.write(
      key: _updatedAtKey(key),
      value: updatedAt.toUtc().toIso8601String(),
    );
  }

  Future<void> deleteRestored(String key, DateTime updatedAt) async {
    await _storage.delete(key: key);
    await _storage.write(
      key: _updatedAtKey(key),
      value: updatedAt.toUtc().toIso8601String(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> delete(String key) async {
    final deletedAt = DateTime.now().toUtc();
    try {
      await _storage.delete(key: key);
      await _storage.write(
        key: _updatedAtKey(key),
        value: deletedAt.toIso8601String(),
      );
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    writeObserver?.call(key, null, deletedAt);
  }

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
}
