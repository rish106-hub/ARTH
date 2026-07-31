import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_account.dart';
import 'secure_storage_service.dart';
import 'server_api_service.dart';

class AuthenticatedSession {
  const AuthenticatedSession({required this.uid, required this.accessToken});

  final String uid;
  final String accessToken;
}

class AuthService {
  static const _accountKey = 'arth_user_account';
  static const _accessTokenKey = 'arth_access_token';
  static const _refreshTokenKey = 'arth_refresh_token';
  static const _requiredResetKey = 'arth_required_session_reset';
  static const _requiredResetVersion = '2026-07-clean-start-v1';

  final ServerApiService _api;
  final SecureStorageService _storage;
  bool _googleInitialized = false;
  Future<UserAccount?>? _refreshInFlight;

  static const _googleServerClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_SERVER_CLIENT_ID',
    defaultValue:
        '101289118169-j0io6jjcdf947ss7bdfpjovk4dacfr4d.apps.googleusercontent.com',
  );

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

  Future<UserAccount> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: _googleServerClientId);
      _googleInitialized = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google did not return an identity token');
    }
    final response = await _api.postJson(
      '/auth/google',
      body: {'idToken': idToken},
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
      final resetVersion = await _storage.read(_requiredResetKey);
      if (resetVersion != _requiredResetVersion) {
        // This is a migration marker, not permission to erase account data.
        // Older builds used this path for a forced clean start, which made an
        // app update look like data loss.
        await _storage.write(_requiredResetKey, _requiredResetVersion);
      }
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

  Future<AuthenticatedSession?> getValidSession() async {
    final accessToken = await getValidAccessToken();
    if (accessToken == null || accessToken.isEmpty) return null;
    final uid = _accessTokenSubject(accessToken);
    if (uid == null || uid.isEmpty) return null;
    return AuthenticatedSession(uid: uid, accessToken: accessToken);
  }

  Future<UserAccount?> refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _refreshSession();
    _refreshInFlight = refresh;
    refresh.then(
      (_) {
        if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
      },
      onError: (_) {
        if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
      },
    );
    return refresh;
  }

  Future<UserAccount?> _refreshSession() async {
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
    } on ServerApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] refresh failed (${e.statusCode})');
      }
      // Only sign out when the SERVER has rejected the refresh token itself.
      // Anything else — no connectivity, a timeout, a 5xx while the backend
      // restarts during a deploy, a rate limit — says nothing about whether the
      // token is still valid, and discarding it there signed every active user
      // out whenever the backend was redeployed.
      if (_isCredentialRejection(e.statusCode)) await clearAccount();
      return null;
    } catch (e) {
      // Unexpected client-side failure. Keep the session for the same reason.
      if (kDebugMode) debugPrint('[AuthService] refresh failed');
      return null;
    }
  }

  /// Retries once after the server rejects a locally unexpired access token.
  /// This happens after a signing-key rotation or server-side session revoke.
  Future<T> withFreshAccessToken<T>(
    Future<T> Function(String accessToken) request,
  ) async {
    final initialToken = await getValidAccessToken();
    if (initialToken == null || initialToken.isEmpty) {
      throw StateError('not signed in');
    }

    try {
      return await request(initialToken);
    } on ServerApiException catch (error) {
      if (error.statusCode != 401) rethrow;
    }

    final account = await refreshSession();
    final replacementToken = await getAccessToken();
    if (account == null ||
        replacementToken == null ||
        replacementToken.isEmpty) {
      throw const ServerApiException(
        401,
        'Your session has expired. Please sign in again.',
        code: 'session_expired',
      );
    }
    return request(replacementToken);
  }

  /// Whether [statusCode] means the server refused the credential itself, as
  /// opposed to failing to answer. 401 is an invalid, expired or already-rotated
  /// refresh token; 403 a revoked one. Only these justify erasing the session.
  static bool _isCredentialRejection(int statusCode) =>
      statusCode == 401 || statusCode == 403;

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
    await Future.wait([
      _storage.delete(_accountKey),
      _storage.delete(_accessTokenKey),
      _storage.delete(_refreshTokenKey),
    ], eagerError: false);
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

    await _storage.write(_requiredResetKey, _requiredResetVersion);
    await _storage.write(_accountKey, account.toJsonString());
    await _storage.write(_accessTokenKey, accessToken);
    await _storage.write(_refreshTokenKey, refreshToken);
    return account;
  }

  bool _isExpired(String jwt) {
    try {
      final payload = _decodeJwtPayload(jwt);
      if (payload == null) return true;
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

  String? _accessTokenSubject(String jwt) {
    final payload = _decodeJwtPayload(jwt);
    if (payload?['type'] != 'access') return null;
    return payload?['sub'] as String?;
  }

  Map<String, dynamic>? _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final normalized = base64.normalize(parts[1]);
      return jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
