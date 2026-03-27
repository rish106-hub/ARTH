import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';
import '../services/cloud_sync_service.dart';

const _kProfileKey = 'arth_user_profile';
const _kOnboardingDoneKey = 'arth_onboarding_complete';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() => const UserProfile();

  void update(UserProfile updated) => state = updated;

  void updateField(UserProfile Function(UserProfile) updater) {
    state = updater(state);
  }

  Future<void> save() async {
    // Save to local storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileKey, state.toJsonString());
    await prefs.setBool(_kOnboardingDoneKey, true);

    // Sync to Firebase
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final cloudSync = CloudSyncService();
      // Create account object from profile name/email
      final account = UserAccount(
        name: state.name,
        email: state.email,
        uid: user.uid,
        createdAt: DateTime.now(),
      );
      // Sync name/email to users/{uid} doc
      await cloudSync.syncAccount(account);
      // Sync tax profile to users/{uid}/tax_profiles/{fy}
      await cloudSync.syncProfile(user.uid, state);
    }
  }

  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kProfileKey);
    if (json != null) {
      try {
        state = UserProfile.fromJsonString(json);
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDoneKey) ?? false;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfileKey);
    await prefs.remove(_kOnboardingDoneKey);
    state = const UserProfile();
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

// Total visible steps: Q00 Name (0) + Q00 Email (1) + Q01-Q12 tax questions (2-13) = 14 steps
const int kTotalSteps = 14;
