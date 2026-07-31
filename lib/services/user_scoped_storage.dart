import 'secure_storage_service.dart';

/// Canonical secure-storage keys for data that belongs to one ARTH account.
/// Every key includes the server-issued user UUID so accounts on a shared
/// device never read each other's caches.
class UserScopedStorageKeys {
  UserScopedStorageKeys._();

  static List<String> get durableNamespaces =>
      durableForUser('').keys.toList(growable: false);

  static String profile(String uid) => 'arth_profile_$uid';
  static String onboarding(String uid) => 'arth_onboarding_$uid';
  static String accountProfile(String uid) => 'arth_account_profile_$uid';
  static String taxYear(String uid) => 'arth_tax_year_$uid';
  static String documentChecklist(String uid) => 'arth_document_checklist_$uid';
  static String spendMap(String uid) => 'arth_spend_map_$uid';
  static String spendMapRecalculationNotice(String uid) =>
      'arth_spend_map_recalculation_notice_$uid';
  static String spendMapAdjustments(String uid) =>
      'arth_spend_map_adjustments_$uid';
  static String spendCategoryRules(String uid) =>
      'arth_spend_category_rules_$uid';

  /// Payees the AI pass has already resolved. Local-only, unlike
  /// [spendCategoryRules]: it is a paid-lookup cache rather than the user's own
  /// corrections, and the server can regenerate it, so it is not worth a durable
  /// namespace. Its job is to stop a re-scan paying to classify a payee twice.
  static String spendCategoryAiMemory(String uid) =>
      'arth_spend_category_ai_memory_$uid';
  static String spendCompleteness(String uid) => 'arth_spend_completeness_$uid';
  static String otherIncome(String uid) => 'arth_other_income_$uid';
  static String otherIncomeAsked(String uid) => 'arth_other_income_asked_$uid';
  static String paycheckOverrides(String uid) => 'arth_paycheck_overrides_$uid';
  static String syncQueue(String uid) => 'arth_sync_queue_$uid';
  static String recovery(String uid) => 'arth_recovery_$uid';
  static String monthlyClose(String uid) => 'arth_monthly_close_$uid';

  static Map<String, String> durableForUser(String uid) => {
        'profile-draft': profile(uid),
        'onboarding': onboarding(uid),
        'tax-year': taxYear(uid),
        'document-checklist': documentChecklist(uid),
        'spend-map': spendMap(uid),
        'spend-map-adjustments': spendMapAdjustments(uid),
        'spend-category-rules': spendCategoryRules(uid),
        'spend-completeness': spendCompleteness(uid),
        'other-income': otherIncome(uid),
        'other-income-asked': otherIncomeAsked(uid),
        'paycheck-overrides': paycheckOverrides(uid),
        'recovery': recovery(uid),
        'monthly-close': monthlyClose(uid),
      };

  static String? durableNamespaceForKey(String uid, String key) {
    for (final entry in durableForUser(uid).entries) {
      if (entry.value == key) return entry.key;
    }
    return null;
  }

  static bool isDurableKey(String key) {
    return durableForUser('').values.any(
          (prefix) => key.length > prefix.length && key.startsWith(prefix),
        );
  }

  static List<String> allForUser(String uid) => [
        profile(uid),
        onboarding(uid),
        accountProfile(uid),
        taxYear(uid),
        documentChecklist(uid),
        spendMap(uid),
        spendMapRecalculationNotice(uid),
        spendMapAdjustments(uid),
        spendCategoryRules(uid),
        spendCategoryAiMemory(uid),
        spendCompleteness(uid),
        otherIncome(uid),
        otherIncomeAsked(uid),
        paycheckOverrides(uid),
        syncQueue(uid),
        recovery(uid),
        monthlyClose(uid),
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
