import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';

class AuthNotifier extends StateNotifier<UserAccount?> {
  final AuthService _service;

  AuthNotifier(this._service) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final account = await _service.loadAccount();
    state = account;
  }

  Future<void> saveAccount(UserAccount account) async {
    await _service.saveAccount(account);
    state = account;
  }

  Future<void> signOut() async {
    await _service.clearAccount();
    state = null;
  }

  Future<bool> hasBiometrics() => _service.hasBiometrics();

  Future<bool> authenticate() => _service.authenticate();

  bool get isLoggedIn => state != null;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});
