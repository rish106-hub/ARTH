import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Remote Config helper ───────────────────────────────────────────────────
/// Fetches Remote Config flags once per app session.
/// Fails silently and keeps local defaults when Firebase is unavailable.
final _remoteConfigProvider = FutureProvider<Map<String, bool>>((ref) async {
  const defaults = {
    'budget_alert_enabled': true,
  };

  if (Firebase.apps.isEmpty) {
    return defaults;
  }

  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc.setDefaults(defaults);
    await rc.fetchAndActivate();
    return {
      'budget_alert_enabled': rc.getBool('budget_alert_enabled'),
    };
  } catch (_) {
    return defaults;
  }
});

/// Controls whether the Budget Alert feature is active.
final budgetAlertEnabledProvider = FutureProvider<bool>((ref) async {
  final flags = await ref.watch(_remoteConfigProvider.future);
  return flags['budget_alert_enabled'] ?? true;
});
