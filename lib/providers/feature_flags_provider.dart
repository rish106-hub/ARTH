import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/google_auth_service.dart';
import '../services/phone_auth_service.dart';

// ── Google Auth Service ────────────────────────────────────────────────────
final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (_) => GoogleAuthService(),
);

// ── Phone Auth Service ─────────────────────────────────────────────────────
final phoneAuthServiceProvider = Provider<PhoneAuthService>(
  (_) => PhoneAuthService(),
);

// ── Remote Config helper ───────────────────────────────────────────────────
/// Fetches all Remote Config flags once per app session.
/// Fails silently — defaults to true so both auth methods work out of the box.
final _remoteConfigProvider = FutureProvider<FirebaseRemoteConfig>((ref) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults({
      // Both enabled — Firebase project arth-tax-gap is live.
      'google_sign_in_enabled': true,
      'phone_otp_enabled': true,
    });
    await rc.fetchAndActivate();
    return rc;
  } catch (_) {
    return FirebaseRemoteConfig.instance;
  }
});

// ── Individual feature flags ───────────────────────────────────────────────

/// Controls whether the Google Sign-In button is active.
/// Toggle: Firebase Console → Remote Config → `google_sign_in_enabled`
final googleSignInEnabledProvider = FutureProvider<bool>((ref) async {
  final rc = await ref.watch(_remoteConfigProvider.future);
  return rc.getBool('google_sign_in_enabled');
});

/// Controls whether phone OTP verification is required at sign-in.
/// Toggle: Firebase Console → Remote Config → `phone_otp_enabled`
final phoneOtpEnabledProvider = FutureProvider<bool>((ref) async {
  final rc = await ref.watch(_remoteConfigProvider.future);
  return rc.getBool('phone_otp_enabled');
});
