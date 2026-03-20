import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user_account.dart';
import 'cloud_sync_service.dart';

/// Local + cloud authentication service.
///
/// On first account creation:
///   1. Save account to SharedPreferences (offline-first)
///   2. Sign in anonymously via Firebase → get stable UID
///   3. Persist updated account with UID back to SharedPreferences
///   4. Sync account doc to Firestore in background
///
/// On subsequent opens:
///   • Load from SharedPreferences instantly (no network wait)
///   • Silently update last_seen in Firestore
class AuthService {
  static const _accountKey = 'arth_user_account';

  final LocalAuthentication _localAuth = LocalAuthentication();
  final CloudSyncService _cloud = CloudSyncService();

  // ── Biometrics ────────────────────────────────────────────────────────────
  Future<bool> hasBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Verify your identity to access ARTH',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ── Account persistence ───────────────────────────────────────────────────
  Future<void> saveAccount(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();

    // Step 1: save immediately for instant local load
    await prefs.setString(_accountKey, account.toJsonString());

    // Step 2: get Firebase UID (anonymous) if not already assigned
    if (account.uid == null) {
      final uid = await _cloud.ensureAnonymousUid();
      if (uid != null) {
        final withUid = account.copyWith(uid: uid);
        // Save again with UID so subsequent loads include it
        await prefs.setString(_accountKey, withUid.toJsonString());
        // Sync to Firestore in background — don't await
        _cloud.syncAccount(withUid).catchError(
          (e) {
            if (kDebugMode)
              debugPrint('[AuthService] background sync failed: $e');
          },
        );
      }
    } else {
      // Already has UID — just sync in background
      _cloud.syncAccount(account).catchError(
        (e) {
          if (kDebugMode)
            debugPrint('[AuthService] background sync failed: $e');
        },
      );
    }
  }

  Future<UserAccount?> loadAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountKey);
      if (raw == null || raw.isEmpty) return null;
      return UserAccount.fromJsonString(raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] loadAccount failed: $e');
      return null;
    }
  }

  Future<void> clearAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountKey);
    await _cloud.signOut();
  }

  Future<bool> get isLoggedIn async {
    final account = await loadAccount();
    return account != null;
  }
}
