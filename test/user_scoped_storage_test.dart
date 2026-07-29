import 'package:arth/services/user_scoped_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserScopedStorageKeys lists every per-user cache key', () {
    const uid = 'user-123';
    final keys = UserScopedStorageKeys.allForUser(uid);
    expect(keys, contains(UserScopedStorageKeys.profile(uid)));
    expect(keys, contains(UserScopedStorageKeys.onboarding(uid)));
    expect(keys, contains(UserScopedStorageKeys.accountProfile(uid)));
    expect(keys, contains(UserScopedStorageKeys.taxYear(uid)));
    expect(keys, contains(UserScopedStorageKeys.documentChecklist(uid)));
    expect(keys, contains(UserScopedStorageKeys.spendMap(uid)));
    expect(keys, contains(UserScopedStorageKeys.spendMapAdjustments(uid)));
    expect(keys, contains(UserScopedStorageKeys.spendCompleteness(uid)));
    expect(keys, contains(UserScopedStorageKeys.otherIncome(uid)));
    expect(keys, contains(UserScopedStorageKeys.otherIncomeAsked(uid)));
    expect(keys, contains(UserScopedStorageKeys.paycheckOverrides(uid)));
    expect(keys, contains(UserScopedStorageKeys.syncQueue(uid)));
    expect(keys, contains(UserScopedStorageKeys.recovery(uid)));
    expect(keys, contains(UserScopedStorageKeys.monthlyClose(uid)));
    expect(keys.length, 14);
  });

  test('durable keys include drafts and exclude auth caches and retry queue',
      () {
    const uid = 'user-123';
    final durable = UserScopedStorageKeys.durableForUser(uid);

    expect(durable.keys, UserScopedStorageKeys.durableNamespaces);
    expect(durable.values, contains(UserScopedStorageKeys.profile(uid)));
    expect(durable.values, contains(UserScopedStorageKeys.onboarding(uid)));
    expect(durable.values, contains(UserScopedStorageKeys.taxYear(uid)));
    expect(
      durable.values,
      isNot(contains(UserScopedStorageKeys.accountProfile(uid))),
    );
    expect(
      durable.values,
      isNot(contains(UserScopedStorageKeys.syncQueue(uid))),
    );
    for (final entry in durable.entries) {
      expect(
        UserScopedStorageKeys.durableNamespaceForKey(uid, entry.value),
        entry.key,
      );
      expect(UserScopedStorageKeys.isDurableKey(entry.value), isTrue);
    }
    expect(UserScopedStorageKeys.isDurableKey('arth_access_token'), isFalse);
  });
}
