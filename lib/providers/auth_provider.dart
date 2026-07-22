import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';

class AuthNotifier extends Notifier<UserAccount?> {
  final AuthService? _overrideService;
  AuthService? _service;

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
    final account = await _resolvedService.loadAccount();
    if (!ref.mounted) return;
    state = account;
  }

  Future<void> saveAccount(UserAccount account) async {
    await _resolvedService.saveAccount(account);
    if (!ref.mounted) return;
    state = account;
  }

  Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final account = await _resolvedService.signUp(
      name: name,
      email: email,
      password: password,
    );
    if (ref.mounted) state = account;
    return account;
  }

  Future<UserAccount> signIn({
    required String email,
    required String password,
  }) async {
    final account =
        await _resolvedService.signIn(email: email, password: password);
    if (ref.mounted) state = account;
    return account;
  }

  Future<void> signOut() async {
    await _resolvedService.clearAccount();
    if (!ref.mounted) return;
    state = null;
  }

  bool get isLoggedIn => state != null;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = NotifierProvider<AuthNotifier, UserAccount?>(
  AuthNotifier.new,
);
