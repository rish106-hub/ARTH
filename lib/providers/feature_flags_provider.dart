import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Remote Config helper ───────────────────────────────────────────────────
/// Fetches Remote Config flags once per app session.
/// Fails silently — returns instance with defaults on error.
final _remoteConfigProvider = FutureProvider<FirebaseRemoteConfig>((ref) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults({
      'budget_alert_enabled': true,
    });
    await rc.fetchAndActivate();
    return rc;
  } catch (_) {
    return FirebaseRemoteConfig.instance;
  }
});

/// Controls whether the Budget Alert feature is active.
final budgetAlertEnabledProvider = FutureProvider<bool>((ref) async {
  final rc = await ref.watch(_remoteConfigProvider.future);
  return rc.getBool('budget_alert_enabled');
});
