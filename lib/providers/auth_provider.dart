import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';

class AuthNotifier extends Notifier<UserAccount?> {
  final AuthService? _overrideService;
  AuthService? _service;
  int _operationId = 0;

  AuthNotifier([this._overrideService]);

  @override
  UserAccount? build() {
    _load();
    return null;
  }

  AuthService get _resolvedService {
    final existing = _service;
    if (existing != null) return existing;
    final AuthService resolved =
        _overrideService ?? ref.read(authServiceProvider);
    _service = resolved;
    return resolved;
  }

  Future<void> _load() async {
    final operationId = _operationId;
    final account = await _resolvedService.loadAccount();
    if (!ref.mounted || operationId != _operationId) return;
    state = account;
    if (account != null) _syncPushToken();
  }

  /// Registers this device's FCM token for the signed-in user. Best-effort —
  /// [PushNotificationService.syncToken] swallows its own errors, so a missing
  /// permission or offline device never blocks auth.
  Future<void> _syncPushToken() async {
    final token = await _resolvedService.getValidAccessToken();
    if (token == null || !ref.mounted) return;
    await ref.read(pushNotificationServiceProvider).syncToken(token);
  }

  Future<void> saveAccount(UserAccount account) async {
    ++_operationId;
    await _resolvedService.saveAccount(account);
    if (!ref.mounted) return;
    state = account;
  }

  Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final operationId = ++_operationId;
    final account = await _resolvedService.signUp(
      name: name,
      email: email,
      password: password,
    );
    if (ref.mounted && operationId == _operationId) {
      state = account;
      _syncPushToken();
    }
    return account;
  }

  Future<UserAccount> signIn({
    required String email,
    required String password,
  }) async {
    final operationId = ++_operationId;
    final account =
        await _resolvedService.signIn(email: email, password: password);
    if (ref.mounted && operationId == _operationId) {
      state = account;
      _syncPushToken();
    }
    return account;
  }

  Future<UserAccount> signInWithGoogle() async {
    final operationId = ++_operationId;
    final account = await _resolvedService.signInWithGoogle();
    if (ref.mounted && operationId == _operationId) {
      state = account;
      _syncPushToken();
    }
    return account;
  }

  Future<void> signOut() async {
    ++_operationId;
    final token = await _resolvedService.getValidAccessToken();
    if (token != null) {
      await ref.read(pushNotificationServiceProvider).unregister(token);
    }
    await _resolvedService.clearAccount();
    if (!ref.mounted) return;
    state = null;
  }

  bool get isLoggedIn => state != null;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) => pushNotificationService);

final authProvider = NotifierProvider<AuthNotifier, UserAccount?>(
  AuthNotifier.new,
);
