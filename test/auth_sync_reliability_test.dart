import 'dart:convert';

import 'package:arth/models/user_profile.dart';
import 'package:arth/services/auth_service.dart';
import 'package:arth/services/backend_sync_service.dart';
import 'package:arth/services/secure_storage_service.dart';
import 'package:arth/services/server_api_service.dart';
import 'package:arth/services/sync_queue_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('expired access token refreshes and persists new token', () async {
    final expired =
        _jwtWithExpiry(DateTime.now().subtract(const Duration(minutes: 5)));
    final fresh =
        _jwtWithExpiry(DateTime.now().add(const Duration(minutes: 15)));
    final api = _FakeApi()
      ..postResponses['/auth/sign-in'] = _authResponse(expired, 'refresh-1')
      ..postResponses['/auth/refresh'] = _authResponse(fresh, 'refresh-2');
    final auth = AuthService(api: api);

    await auth.signIn(email: 'user@example.com', password: 'CorrectHorse9');
    final token = await auth.getValidAccessToken();

    expect(token, fresh);
    expect(api.postCalls, contains('/auth/refresh'));
  });

  test('sign-up retries transient server failures like sign-in', () async {
    final api = _FakeApi()
      ..postResponses['/auth/sign-up'] = _authResponse(
        _jwtWithExpiry(DateTime.now().add(const Duration(minutes: 15))),
        'refresh-1',
      );
    final auth = AuthService(api: api);

    await auth.signUp(
      name: 'User',
      email: 'user@example.com',
      password: 'CorrectHorse9',
    );

    expect(api.postRetryFlags['/auth/sign-up'], isTrue);
  });

  test('refresh failure clears auth tokens but leaves profile storage alone',
      () async {
    final storage = const SecureStorageService();
    final api = _FakeApi()
      ..postResponses['/auth/sign-in'] = _authResponse(
        _jwtWithExpiry(DateTime.now().subtract(const Duration(minutes: 5))),
        'refresh-1',
      )
      ..postErrors['/auth/refresh'] =
          const ServerApiException(401, 'Invalid refresh token');
    final auth = AuthService(api: api, storage: storage);

    await auth.signIn(email: 'user@example.com', password: 'CorrectHorse9');
    await storage.write('arth_user_profile', '{"name":"Local"}');

    final refreshed = await auth.refreshSession();

    expect(refreshed, isNull);
    expect(await auth.loadAccount(), isNull);
    expect(await auth.getAccessToken(), isNull);
    expect(await storage.read('arth_user_profile'), '{"name":"Local"}');
  });

  test(
      'sync queue deduplicates, rejects invalid type, and drops oversized payload',
      () async {
    final queue = const SyncQueueService();

    await queue.enqueue('profile', {'version': 1});
    await queue.enqueue('profile', {'version': 2});
    await queue.enqueue('taxResult', {'ok': true});
    await queue.enqueue('invalid', {'bad': true});
    await queue.enqueue(
        'doneGaps', {'blob': 'x' * (SyncQueueService.maxPayloadBytes + 1)});

    final ops = await queue.popAll();

    expect(ops.map((op) => op.type), ['profile', 'taxResult']);
    expect(ops.first.payload, {'version': 2});
  });

  test('client 4xx sync failure is not queued but server failure is queued',
      () async {
    final auth = _FixedTokenAuthService();
    final queue = _RecordingQueue();
    final api = _FakeApi();
    final sync = BackendSyncService(api: api, auth: auth, queue: queue);

    api.putError = const ServerApiException(400, 'Invalid request');
    await sync.syncProfile(_sampleProfile());
    expect(queue.enqueuedTypes, isEmpty);

    api.putError = const ServerApiException(503, 'Service unavailable');
    await sync.syncProfile(_sampleProfile());
    expect(queue.enqueuedTypes, ['profile']);
  });

  test('missing auth token is not queued for later replay', () async {
    final queue = _RecordingQueue();
    final sync = BackendSyncService(
      api: _FakeApi(),
      auth: _MissingTokenAuthService(),
      queue: queue,
    );

    await sync.syncProfile(_sampleProfile());

    expect(queue.enqueuedTypes, isEmpty);
  });
}

class _FakeApi extends ServerApiService {
  final postResponses = <String, Map<String, dynamic>>{};
  final postErrors = <String, ServerApiException>{};
  final postCalls = <String>[];
  final postRetryFlags = <String, bool>{};
  ServerApiException? putError;

  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool retryTransient = false,
  }) async {
    postCalls.add(path);
    postRetryFlags[path] = retryTransient;
    final error = postErrors[path];
    if (error != null) throw error;
    return postResponses[path] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final error = putError;
    if (error != null) throw error;
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<void> postNoContent(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {}
}

class _FixedTokenAuthService extends AuthService {
  @override
  Future<String?> getValidAccessToken() async => 'access-token';
}

class _MissingTokenAuthService extends AuthService {
  @override
  Future<String?> getValidAccessToken() async => null;
}

class _RecordingQueue extends SyncQueueService {
  final enqueuedTypes = <String>[];

  @override
  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    enqueuedTypes.add(type);
  }
}

Map<String, dynamic> _authResponse(String accessToken, String refreshToken) {
  return {
    'user': {
      'id': 'user-1',
      'name': 'User',
      'email': 'user@example.com',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    },
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

String _jwtWithExpiry(DateTime expiry) {
  final header = _base64UrlNoPadding({'alg': 'none'});
  final payload = _base64UrlNoPadding({
    'sub': 'user-1',
    'email': 'user@example.com',
    'type': 'access',
    'exp': expiry.toUtc().millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.signature';
}

String _base64UrlNoPadding(Map<String, dynamic> value) {
  return base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

UserProfile _sampleProfile() {
  return const UserProfile(
    name: 'User',
    email: 'user@example.com',
    annualCTC: 1800000,
    employmentType: EmploymentType.salaried,
    city: 'Delhi',
    isMetroCity: true,
    paysRent: true,
    monthlyRent: 35000,
    hasHRA: true,
    invested80C: 70000,
    hasHomeLoan: true,
    propertyType: PropertyType.selfOccupied,
    homeLoanInterest: 200000,
    hasNPS: true,
    npsExtraContribution: 50000,
    hasHealthInsuranceSelf: true,
    hasHealthInsuranceParents: true,
    parentsAbove60: true,
    hasEducationLoan: true,
    educationLoanRepaymentYear: 3,
    educationLoanInterest: 60000,
    hasDonations: true,
    donationAmount: 25000,
    ageGroup: AgeGroup.age30to45,
  );
}
