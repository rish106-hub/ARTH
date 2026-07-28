import 'package:arth/services/user_scoped_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserScopedStorageKeys lists every per-user cache key', () {
    const uid = 'user-123';
    final keys = UserScopedStorageKeys.allForUser(uid);
    expect(keys, contains(UserScopedStorageKeys.profile(uid)));
    expect(keys, contains(UserScopedStorageKeys.onboarding(uid)));
    expect(keys, contains(UserScopedStorageKeys.accountProfile(uid)));
    expect(keys, contains(UserScopedStorageKeys.documentChecklist(uid)));
    expect(keys, contains(UserScopedStorageKeys.spendMap(uid)));
    expect(keys, contains(UserScopedStorageKeys.spendMapAdjustments(uid)));
    expect(keys, contains(UserScopedStorageKeys.otherIncome(uid)));
    expect(keys, contains(UserScopedStorageKeys.otherIncomeAsked(uid)));
    expect(keys, contains(UserScopedStorageKeys.paycheckOverrides(uid)));
    expect(keys, contains(UserScopedStorageKeys.syncQueue(uid)));
    expect(keys, contains(UserScopedStorageKeys.recovery(uid)));
    expect(keys.length, 11);
  });
}
