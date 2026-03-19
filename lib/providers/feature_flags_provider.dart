import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/google_auth_service.dart';

// ── Google Auth Service ────────────────────────────────────────────────────
final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (_) => GoogleAuthService(),
);

// ── Remote Config helper ───────────────────────────────────────────────────
/// Fetches all Remote Config flags once per app session.
/// Fails silently — all flags default to false when Firebase is unavailable.
final _remoteConfigProvider = FutureProvider<FirebaseRemoteConfig>((ref) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults({'google_sign_in_enabled': false});
    await rc.fetchAndActivate();
    return rc;
  } catch (_) {
    // Return default-values-only instance if Firebase is not configured
    return FirebaseRemoteConfig.instance;
  }
});

// ── Individual feature flags ───────────────────────────────────────────────

/// Controls whether the Google Sign-In button is active.
/// Toggle in Firebase Console → Remote Config → `google_sign_in_enabled`
final googleSignInEnabledProvider = FutureProvider<bool>((ref) async {
  final rc = await ref.watch(_remoteConfigProvider.future);
  return rc.getBool('google_sign_in_enabled');
});
