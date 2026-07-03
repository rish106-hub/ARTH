import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user_account.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';

class AuthService {
  static const _accountKey = 'arth_user_account';
  static const _accessTokenKey = 'arth_access_token';
  static const _refreshTokenKey = 'arth_refresh_token';

  final ServerApiService _api;
  final SecureStorageService _storage;

  AuthService({ServerApiService? api, SecureStorageService? storage})
      : _api = api ?? ServerApiService(),
        _storage = storage ?? const SecureStorageService();

  Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _api.postJson(
      '/auth/sign-up',
      body: {'name': name, 'email': email, 'password': password},
      retryTransient: true,
    );
    return _persistAuthResponse(response);
  }

  Future<UserAccount> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _api.postJson(
      '/auth/sign-in',
      body: {'email': email, 'password': password},
      retryTransient: true,
    );
    return _persistAuthResponse(response);
  }

  Future<void> saveAccount(UserAccount account) async {
    await _storage.write(_accountKey, account.toJsonString());
  }

  Future<UserAccount?> loadAccount() async {
    try {
      final raw = await _storage.read(_accountKey, migrateFromPrefs: true);
      if (raw == null || raw.isEmpty) return null;
      return UserAccount.fromJsonString(raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] loadAccount failed');
      return null;
    }
  }

  Future<String?> getAccessToken() async {
    return _storage.read(_accessTokenKey, migrateFromPrefs: true);
  }

  Future<String?> getValidAccessToken() async {
    final current = await getAccessToken();
    if (current != null && current.isNotEmpty && !_isExpired(current)) {
      return current;
    }

    final refreshed = await refreshSession();
    if (refreshed == null) return null;
    return getAccessToken();
  }

  Future<UserAccount?> refreshSession() async {
    final refreshToken = await _storage.read(
      _refreshTokenKey,
      migrateFromPrefs: true,
    );
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await _api.postJson(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      return _persistAuthResponse(response);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] refresh failed');
      await clearAccount();
      return null;
    }
  }

  Future<void> clearAccount() async {
    final refreshToken = await _storage.read(
      _refreshTokenKey,
      migrateFromPrefs: true,
    );
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.postNoContent(
          '/auth/sign-out',
          body: {'refreshToken': refreshToken},
        );
      } catch (_) {}
    }
    await Future.wait(
      [
        _storage.delete(_accountKey),
        _storage.delete(_accessTokenKey),
        _storage.delete(_refreshTokenKey),
      ],
      eagerError: false,
    );
  }

  Future<UserAccount> _persistAuthResponse(
    Map<String, dynamic> response,
  ) async {
    final user = response['user'] as Map<String, dynamic>;
    final account = UserAccount(
      uid: user['id'] as String?,
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      phoneNumber: user['phoneNumber'] as String?,
      avatarInitials: user['avatarInitials'] as String?,
      avatarColor: user['avatarColor'] as String?,
      createdAt: DateTime.parse(
        user['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );

    final accessToken = response['accessToken'] as String? ?? '';
    final refreshToken = response['refreshToken'] as String? ?? '';

    await _storage.write(_accountKey, account.toJsonString());
    await _storage.write(_accessTokenKey, accessToken);
    await _storage.write(_refreshTokenKey, refreshToken);
    return account;
  }

  bool _isExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return true;
      final normalized = base64.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      final exp = payload['exp'] as num?;
      if (exp == null) return true;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      return DateTime.now().toUtc().isAfter(
            expiresAt.subtract(const Duration(minutes: 1)),
          );
    } catch (_) {
      return true;
    }
  }
}
