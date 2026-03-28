import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';

class AuthNotifier extends StateNotifier<UserAccount?> {
  final AuthService _service;

  AuthNotifier(this._service) : super(null) {
    _load();
  }

  Future<void> _load() async {
    state = await _service.loadAccount();
  }

  Future<void> saveAccount(UserAccount account) async {
    await _service.saveAccount(account);
    state = account;
  }

  Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final account = await _service.signUp(
      name: name,
      email: email,
      password: password,
    );
    state = account;
    return account;
  }

  Future<UserAccount> signIn({
    required String email,
    required String password,
  }) async {
    final account = await _service.signIn(
      email: email,
      password: password,
    );
    state = account;
    return account;
  }

  Future<void> signOut() async {
    await _service.clearAccount();
    state = null;
  }

  bool get isLoggedIn => state != null;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});
