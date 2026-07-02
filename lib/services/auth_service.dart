import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_account.dart';
import 'server_api_service.dart';

class AuthService {
  static const _accountKey = 'arth_user_account';
  static const _accessTokenKey = 'arth_access_token';
  static const _refreshTokenKey = 'arth_refresh_token';

  final ServerApiService _api;

  AuthService({ServerApiService? api}) : _api = api ?? ServerApiService();

  Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _api.postJson(
      '/auth/sign-up',
      body: {'name': name, 'email': email, 'password': password},
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
    );
    return _persistAuthResponse(response);
  }

  Future<void> saveAccount(UserAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, account.toJsonString());
  }

  Future<UserAccount?> loadAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountKey);
      if (raw == null || raw.isEmpty) return null;
      return UserAccount.fromJsonString(raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] loadAccount failed: $e');
      return null;
    }
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
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
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await _api.postJson(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      return _persistAuthResponse(response);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] refresh failed: $e');
      await clearAccount();
      return null;
    }
  }

  Future<void> clearAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.postNoContent(
          '/auth/sign-out',
          body: {'refreshToken': refreshToken},
        );
      } catch (_) {}
    }
    await prefs.remove(_accountKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<UserAccount> _persistAuthResponse(
    Map<String, dynamic> response,
  ) async {
    final user = response['user'] as Map<String, dynamic>;
    final account = UserAccount(
      uid: user['id'] as String?,
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      createdAt: DateTime.parse(
        user['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );

    final accessToken = response['accessToken'] as String? ?? '';
    final refreshToken = response['refreshToken'] as String? ?? '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, account.toJsonString());
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    return account;
  }

  bool _isExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return true;
      final normalized = base64.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized)))
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
