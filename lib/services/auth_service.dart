import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user_account.dart';
import 'cloud_sync_service.dart';

/// Simple local auth service — stores name + email in SharedPreferences.
/// On first save, also gets an anonymous Firebase UID for Firestore sync.
class AuthService {
  static const _accountKey = 'arth_user_account';
  final CloudSyncService _cloud = CloudSyncService();

  Future<void> saveAccount(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, account.toJsonString());

    // Get Firebase anonymous UID in background if not yet assigned
    if (account.uid == null) {
      final uid = await _cloud.ensureAnonymousUid();
      if (uid != null) {
        final withUid = account.copyWith(uid: uid);
        await prefs.setString(_accountKey, withUid.toJsonString());
        _cloud.syncAccount(withUid).catchError((e) {
          if (kDebugMode) debugPrint('[AuthService] sync failed: $e');
        });
      }
    } else {
      _cloud.syncAccount(account).catchError((e) {
        if (kDebugMode) debugPrint('[AuthService] sync failed: $e');
      });
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
}
