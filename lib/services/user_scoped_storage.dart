import 'secure_storage_service.dart';

/// Canonical secure-storage keys for data that belongs to one ARTH account.
/// Every key includes the server-issued user UUID so accounts on a shared
/// device never read each other's caches.
class UserScopedStorageKeys {
  UserScopedStorageKeys._();

  static String profile(String uid) => 'arth_profile_$uid';
  static String onboarding(String uid) => 'arth_onboarding_$uid';
  static String accountProfile(String uid) => 'arth_account_profile_$uid';
  static String documentChecklist(String uid) => 'arth_document_checklist_$uid';
  static String spendMap(String uid) => 'arth_spend_map_$uid';
  static String spendMapAdjustments(String uid) =>
      'arth_spend_map_adjustments_$uid';
  static String otherIncome(String uid) => 'arth_other_income_$uid';
  static String otherIncomeAsked(String uid) => 'arth_other_income_asked_$uid';
  static String paycheckOverrides(String uid) => 'arth_paycheck_overrides_$uid';
  static String syncQueue(String uid) => 'arth_sync_queue_$uid';

  static List<String> allForUser(String uid) => [
        profile(uid),
        onboarding(uid),
        accountProfile(uid),
        documentChecklist(uid),
        spendMap(uid),
        spendMapAdjustments(uid),
        otherIncome(uid),
        otherIncomeAsked(uid),
        paycheckOverrides(uid),
        syncQueue(uid),
      ];
}

/// Deletes every user-scoped local cache entry for [uid]. Does not touch global
/// session keys (access token, account blob) — callers handle those separately.
Future<void> clearUserScopedLocalData(
  SecureStorageService storage,
  String uid,
) async {
  if (uid.isEmpty) return;
  await Future.wait(
    UserScopedStorageKeys.allForUser(uid).map(storage.delete),
    eagerError: false,
  );
}
