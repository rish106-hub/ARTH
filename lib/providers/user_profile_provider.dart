import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';
import '../models/payslip_tax_prefill.dart';
import '../services/backend_sync_service.dart';
import '../services/secure_storage_service.dart';
import 'auth_provider.dart';

// Keys are scoped per user: arth_profile_{uid}, arth_onboarding_{uid}
String _profileKey(String uid) => 'arth_profile_$uid';
String _onboardingKey(String uid) => 'arth_onboarding_$uid';

class UserProfileNotifier extends Notifier<UserProfile> {
  final _storage = const SecureStorageService();
  Timer? _syncDebounce;

  @override
  UserProfile build() {
    ref.onDispose(() => _syncDebounce?.cancel());
    return const UserProfile();
  }

  /// Returns the currently authenticated user's server ID, or null if not signed in.
  String? _currentUid() => ref.read(authProvider)?.uid;

  void update(UserProfile updated) => state = updated;

  Future<void> restoreDraft(UserProfile profile) async {
    state = profile;
    final uid = _currentUid();
    if (uid != null) {
      await _storage.write(_profileKey(uid), state.toJsonString());
    }
  }

  void updateField(UserProfile Function(UserProfile) updater) {
    state = updater(state);
    _scheduleDraftSync();
  }

  void applyPayslipPrefill(PayslipTaxPrefill prefill) {
    state = prefill.applyTo(state);
    _scheduleDraftSync();
  }

  void applyAccountIdentity(UserAccount account) {
    state = state.copyWith(name: account.name, email: account.email);
  }

  /// Starts from a clean profile whenever the authenticated account changes.
  /// This prevents fields from the previous in-memory profile being shown while
  /// the new account's server data is loading or when it has no saved profile.
  void resetForAccount(UserAccount account) {
    _syncDebounce?.cancel();
    state = UserProfile(
      name: account.name,
      email: account.email,
      annualCTC: 0,
      city: '',
    );
  }

  /// Persists the completed profile to server (source of truth) and caches locally.
  /// This is the only method that syncs to the server — draft changes are kept
  /// local-only via _scheduleDraftSync to avoid false "onboarding complete" routing.
  Future<bool> save() async {
    final uid = _currentUid();
    if (uid != null) {
      await _storage.write(_profileKey(uid), state.toJsonString());
      await _storage.write(_onboardingKey(uid), true.toString());
    }
    return _syncCompletedProfile();
  }

  /// Loads this user's profile — server is source of truth.
  /// Falls back to local cache only when the server is unreachable (offline).
  Future<bool> load() async {
    final uid = _currentUid();
    final account = ref.read(authProvider);
    if (account != null) {
      resetForAccount(account);
    } else {
      state = const UserProfile();
    }

    // 0. Replay any ops that failed in a previous session before fetching,
    //    so the server state is up-to-date when we read it back.
    await BackendSyncService().flushPendingQueue();

    // 1. Fetch from server — always the authoritative copy.
    final remote = await BackendSyncService().fetchProfile();
    if (remote != null) {
      state = remote;
      // Update local cache for this user.
      if (uid != null) {
        await _storage.write(_profileKey(uid), remote.toJsonString());
        await _storage.write(_onboardingKey(uid), true.toString());
      }
      return true;
    }

    // 2. Offline fallback — use user-scoped local cache only.
    if (uid != null) {
      final json =
          await _storage.read(_profileKey(uid), migrateFromPrefs: true);
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
    final raw =
        await _storage.read(_onboardingKey(uid), migrateFromPrefs: true);
    return raw == true.toString();
  }

  /// Clears all local state for the current user and wipes all server-side data.
  Future<void> clearAll() async {
    await clearLocalOnly();
    // Delete all server data: profile, tax results, done-gaps.
    await BackendSyncService().deleteAllData();
  }

  /// Clears this device's cached profile for the current user only.
  Future<void> clearLocalOnly() async {
    final uid = _currentUid();
    if (uid != null) {
      await _storage.delete(_profileKey(uid));
      await _storage.delete(_onboardingKey(uid));
    }
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
        await _storage.write(_profileKey(uid), state.toJsonString());
      }
    });
  }

  /// Called after onboarding is fully complete to sync the completed profile
  /// and fire an analytics event. Separated from draft sync intentionally.
  Future<bool> _syncCompletedProfile() async {
    try {
      final synced = await BackendSyncService().syncProfile(state);
      if (!synced) return false;
      await BackendSyncService().trackEvent(
        name: 'profile_updated',
        metadata: {
          'annualCTC': state.annualCTC,
          'employmentType': state.employmentType.name,
          'city': state.city,
          'ageGroup': state.ageGroup.name,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);

final completedTaxProfileProvider = FutureProvider<bool>((ref) async {
  return ref.read(userProfileProvider.notifier).isOnboardingComplete();
});

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
