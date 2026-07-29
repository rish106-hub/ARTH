import 'package:arth/models/user_account.dart';
import 'package:arth/providers/auth_provider.dart';
import 'package:arth/services/auth_service.dart';
import 'package:arth/services/secure_storage_service.dart';
import 'package:arth/services/user_scoped_storage.dart';
import 'package:arth/utils/session_cleanup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.writeObserver = null;
  });

  test('sign-out clears the session but retains account-scoped data', () async {
    final auth = _SessionOnlyAuthService();
    final container = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);

    const storage = SecureStorageService();
    final key = UserScopedStorageKeys.paycheckOverrides('user-1');
    await storage.write(key, '[{"canonicalKey":"basic","amount":80000}]');

    await clearDeviceSessionForContainer(container);

    expect(auth.cleared, isTrue);
    expect(
      await storage.read(key),
      '[{"canonicalKey":"basic","amount":80000}]',
    );
  });
}

class _SessionOnlyAuthService extends AuthService {
  bool cleared = false;

  @override
  Future<UserAccount?> loadAccount() async => UserAccount(
        uid: 'user-1',
        name: 'User',
        email: 'user@example.com',
        createdAt: DateTime(2026, 7, 29),
      );

  @override
  Future<String?> getValidAccessToken() async => null;

  @override
  Future<void> clearAccount() async {
    cleared = true;
  }
}
