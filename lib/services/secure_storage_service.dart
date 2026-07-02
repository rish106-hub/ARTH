import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

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
