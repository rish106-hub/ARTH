import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';
import '../services/backend_sync_service.dart';
import 'auth_provider.dart';

// Keys are scoped per user: arth_profile_{uid}, arth_onboarding_{uid}
String _profileKey(String uid) => 'arth_profile_$uid';
String _onboardingKey(String uid) => 'arth_onboarding_$uid';

class UserProfileNotifier extends Notifier<UserProfile> {
  Timer? _syncDebounce;

  @override
  UserProfile build() {
    ref.onDispose(() => _syncDebounce?.cancel());
    return const UserProfile();
  }

  /// Returns the currently authenticated user's server ID, or null if not signed in.
  String? _currentUid() => ref.read(authProvider)?.uid;

  void update(UserProfile updated) => state = updated;

  void updateField(UserProfile Function(UserProfile) updater) {
    state = updater(state);
    _scheduleDraftSync();
  }

  void applyAccountIdentity(UserAccount account) {
    state = state.copyWith(
      name: account.name,
      email: account.email,
    );
  }

  /// Persists the completed profile to server (source of truth) and caches locally.
  /// This is the only method that syncs to the server — draft changes are kept
  /// local-only via _scheduleDraftSync to avoid false "onboarding complete" routing.
  Future<void> save() async {
    final uid = _currentUid();
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey(uid), state.toJsonString());
      await prefs.setBool(_onboardingKey(uid), true);
    }
    await BackendSyncService().syncProfile(state);
    await _syncCompletedProfile();
  }

  /// Loads this user's profile — server is source of truth.
  /// Falls back to local cache only when the server is unreachable (offline).
  Future<bool> load() async {
    final uid = _currentUid();

    // 0. Replay any ops that failed in a previous session before fetching,
    //    so the server state is up-to-date when we read it back.
    await BackendSyncService().flushPendingQueue();

    // 1. Fetch from server — always the authoritative copy.
    final remote = await BackendSyncService().fetchProfile();
    if (remote != null) {
      state = remote;
      // Update local cache for this user.
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_profileKey(uid), remote.toJsonString());
        await prefs.setBool(_onboardingKey(uid), true);
      }
      return true;
    }

    // 2. Offline fallback — use user-scoped local cache only.
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_profileKey(uid));
      if (json != null) {
        try {
          state = UserProfile.fromJsonString(json);
          return true;
        } catch (_) {}
      }
    }

    return false;
  }

  /// Returns true only if this specific user has completed onboarding.
  Future<bool> isOnboardingComplete() async {
    final uid = _currentUid();
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingKey(uid)) ?? false;
  }

  /// Clears all local state for the current user and wipes all server-side data.
  Future<void> clearAll() async {
    final uid = _currentUid();
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey(uid));
      await prefs.remove(_onboardingKey(uid));
    }
    // Delete all server data: profile, tax results, done-gaps.
    await BackendSyncService().deleteAllData();
    state = const UserProfile();
  }

  void _scheduleDraftSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 600), () async {
      // Draft saves are LOCAL ONLY. Sending partial profiles to the server
      // mid-onboarding would cause load() to return true on the next cold
      // start, routing the user to /gap-reveal with incomplete default data.
      // Server sync happens exclusively from save() once onboarding is done.
      final uid = _currentUid();
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_profileKey(uid), state.toJsonString());
      }
    });
  }

  /// Called after onboarding is fully complete to sync the completed profile
  /// and fire an analytics event. Separated from draft sync intentionally.
  Future<void> _syncCompletedProfile() async {
    try {
      await BackendSyncService().syncProfile(state);
      await BackendSyncService().trackEvent(
        name: 'profile_updated',
        metadata: {
          'annualCTC': state.annualCTC,
          'employmentType': state.employmentType.name,
          'city': state.city,
          'ageGroup': state.ageGroup.name,
        },
      );
    } catch (_) {}
  }
}

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);

// ─── ONBOARDING STATE ────────────────────────────────────────────────────────
class OnboardingNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state++;
  void previous() => state > 0 ? state-- : null;
  void goTo(int step) => state = step;
  void reset() => state = 0;
}

final onboardingStepProvider = NotifierProvider<OnboardingNotifier, int>(
  OnboardingNotifier.new,
);

// Total visible steps: Q01-Q12 tax questions = 12 steps.
const int kTotalSteps = 12;
