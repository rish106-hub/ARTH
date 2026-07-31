import 'dart:convert';

import 'package:arth/models/user_profile.dart';
import 'package:arth/models/user_account.dart';
import 'package:arth/providers/user_profile_provider.dart';
import 'package:arth/services/auth_service.dart';
import 'package:arth/services/backend_sync_service.dart';
import 'package:arth/services/durable_user_state_service.dart';
import 'package:arth/services/secure_storage_service.dart';
import 'package:arth/services/server_api_service.dart';
import 'package:arth/services/sync_queue_service.dart';
import 'package:arth/services/user_scoped_storage.dart';
import 'package:arth/providers/tax_readiness_provider.dart';
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
    SecureStorageService.resetServerClockForTests();
  });

  test('document checklist provider can rebuild without reinitializing storage',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(documentChecklistProvider);
    final notifier = container.read(documentChecklistProvider.notifier);

    expect(notifier.build, returnsNormally);
    expect(notifier.build, returnsNormally);
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

  test('server-rejected access token refreshes once and retries requests',
      () async {
    final stale =
        _jwtWithExpiry(DateTime.now().add(const Duration(minutes: 15)));
    final fresh =
        _jwtWithExpiry(DateTime.now().add(const Duration(minutes: 30)));
    final api = _FakeApi()
      ..postResponses['/auth/sign-in'] = _authResponse(stale, 'refresh-1')
      ..postResponses['/auth/refresh'] = _authResponse(fresh, 'refresh-2');
    final auth = AuthService(api: api);
    final usedTokens = <String>[];

    await auth.signIn(email: 'user@example.com', password: 'CorrectHorse9');

    Future<String> request(String token) async {
      usedTokens.add(token);
      if (token == stale) {
        throw const ServerApiException(401, 'Invalid or expired access token');
      }
      return 'ok';
    }

    final results = await Future.wait([
      auth.withFreshAccessToken(request),
      auth.withFreshAccessToken(request),
    ]);

    expect(results, ['ok', 'ok']);
    expect(
        api.postCalls.where((path) => path == '/auth/refresh'), hasLength(1));
    expect(usedTokens.where((token) => token == fresh), hasLength(2));
  });

  test('version migration retains the account and every existing cache',
      () async {
    final storage = const SecureStorageService();
    final account = UserAccount(
      uid: 'old-user',
      name: 'Old User',
      email: 'old@example.com',
      createdAt: DateTime(2026, 1, 1),
    );
    await storage.write('arth_user_account', account.toJsonString());
    await storage.write('arth_access_token', 'old-access');
    await storage.write('arth_refresh_token', 'old-refresh');
    await storage.write('arth_profile_old-user', '{"name":"Old User"}');
    await storage.write('arth_account_profile_old-user', '{"old":true}');
    await storage.write('arth_sync_queue', '[{"old":true}]');

    final loaded = await AuthService(storage: storage).loadAccount();

    expect(loaded?.uid, 'old-user');
    expect(await storage.read('arth_user_account'), account.toJsonString());
    expect(await storage.read('arth_access_token'), 'old-access');
    expect(await storage.read('arth_refresh_token'), 'old-refresh');
    expect(await storage.read('arth_profile_old-user'), '{"name":"Old User"}');
    expect(
      await storage.read('arth_account_profile_old-user'),
      '{"old":true}',
    );
    expect(await storage.read('arth_sync_queue'), '[{"old":true}]');
    expect(
      await storage.read('arth_required_session_reset'),
      '2026-07-clean-start-v1',
    );
  });

  test('durable state restores a missing device cache from the server',
      () async {
    final storage = const SecureStorageService();
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': [
          {
            'namespace': 'paycheck-overrides',
            'payload': '[{"canonicalKey":"basic","amount":80000}]',
            'clientUpdatedAt': '2026-07-29T10:00:00.000Z',
          },
        ],
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(
      await storage.read(UserScopedStorageKeys.paycheckOverrides('user-1')),
      '[{"canonicalKey":"basic","amount":80000}]',
    );
    expect(
      await storage
          .updatedAt(UserScopedStorageKeys.paycheckOverrides('user-1')),
      DateTime.parse('2026-07-29T10:00:00.000Z'),
    );
  });

  test('a newer server tombstone removes stale device state', () async {
    final storage = const SecureStorageService();
    final key = UserScopedStorageKeys.otherIncome('user-1');
    await storage.write(
      key,
      '[{"id":"1","label":"Freelance","monthlyAmount":20000}]',
    );
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': [
          {
            'namespace': 'other-income',
            'payload': null,
            'deleted': true,
            'clientUpdatedAt': '2027-07-29T10:00:00.000Z',
          },
        ],
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(await storage.read(key), isNull);
    expect(await storage.updatedAt(key), DateTime.parse('2027-07-29T10:00Z'));
  });

  test('a server tombstone removes legacy state without a local timestamp',
      () async {
    final key = UserScopedStorageKeys.otherIncome('user-1');
    FlutterSecureStorage.setMockInitialValues({
      key: '[{"id":"1","label":"Freelance","monthlyAmount":20000}]',
    });
    final storage = const SecureStorageService();
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': [
          {
            'namespace': 'other-income',
            'payload': null,
            'deleted': true,
            'clientUpdatedAt': '2026-07-29T10:00:00.000Z',
          },
        ],
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(await storage.read(key), isNull);
    expect(api.putBodies, isEmpty);
  });

  test('queued backup keeps the timestamp captured with its value', () async {
    final storage = const SecureStorageService();
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );
    final key = UserScopedStorageKeys.otherIncome('user-1');
    final queuedAt = DateTime.parse('2026-07-29T09:00:00.000Z');
    final restoredAt = DateTime.parse('2026-07-29T10:00:00.000Z');

    service.scheduleBackup(key, 'old-value', queuedAt);
    await storage.writeRestored(key, 'new-value', restoredAt);
    await service.flushScheduled();

    expect(
      api.putBodies['/user-state/other-income'],
      {
        'payload': 'old-value',
        'clientUpdatedAt': queuedAt.toIso8601String(),
      },
    );
  });

  test('an older callback cannot replace a newer queued tombstone', () async {
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: const SecureStorageService(),
    );
    final key = UserScopedStorageKeys.otherIncome('user-1');
    final deletedAt = DateTime.parse('2026-07-29T10:00:00.000Z');
    final staleWriteAt = DateTime.parse('2026-07-29T09:00:00.000Z');

    service.scheduleBackup(key, null, deletedAt);
    service.scheduleBackup(key, 'stale-value', staleWriteAt);
    await service.flushScheduled();

    expect(
      api.deleteBodies['/user-state/other-income'],
      {'clientUpdatedAt': deletedAt.toIso8601String()},
    );
    expect(api.putBodies, isEmpty);
  });

  test('pending state cannot cross accounts during a session switch', () async {
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _BoundSessionAuthService('user-2'),
      api: api,
      storage: const SecureStorageService(),
    );

    service.scheduleBackup(
      UserScopedStorageKeys.otherIncome('user-1'),
      'user-1-value',
    );
    await service.flushScheduled();

    expect(api.putBodies, isEmpty);
    expect(api.deleteBodies, isEmpty);
  });

  test('non-durable auth values never enter the backup queue', () async {
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: const SecureStorageService(),
    );

    service.scheduleBackup('arth_access_token', 'secret-token');
    await service.flushScheduled();

    expect(api.putBodies, isEmpty);
    expect(api.putPaths, isEmpty);
  });

  test('a failed backup stays queued for the next flush', () async {
    final api = _FakeApi()..putError = const ServerApiException(503, 'offline');
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: const SecureStorageService(),
    );
    final key = UserScopedStorageKeys.otherIncome('user-1');

    service.scheduleBackup(key, 'value');
    await service.flushScheduled();
    expect(api.putPaths, ['/user-state/other-income']);

    api.putError = null;
    await service.flushScheduled();
    expect(api.putPaths, [
      '/user-state/other-income',
      '/user-state/other-income',
    ]);
  });

  test('secure storage serializes a value with its matching timestamp',
      () async {
    const storage = SecureStorageService();
    const key = 'serialized-key';
    final observed = <(String?, DateTime)>[];
    SecureStorageService.writeObserver = (changedKey, value, updatedAt) {
      if (changedKey == key) observed.add((value, updatedAt));
    };

    await Future.wait([
      storage.write(key, 'first'),
      storage.write(key, 'second'),
    ]);

    expect(await storage.read(key), 'second');
    expect(observed.map((entry) => entry.$1), ['first', 'second']);
    expect(await storage.updatedAt(key), observed.last.$2);
  });

  test('new writes use the last observed server clock', () async {
    const storage = SecureStorageService();
    final serverTime = DateTime.parse('2027-07-29T10:00:00.000Z');
    SecureStorageService.observeServerTime(serverTime);

    await storage.write('clock-key', 'value');

    final updatedAt = await storage.updatedAt('clock-key');
    expect(updatedAt, isNotNull);
    expect(updatedAt!.isBefore(serverTime), isFalse);
  });

  test('hydration corrects a far-future local timestamp', () async {
    const storage = SecureStorageService();
    final key = UserScopedStorageKeys.otherIncome('user-1');
    final futureAt = DateTime.parse('2030-07-29T10:00:00.000Z');
    final serverTime = DateTime.parse('2026-07-29T10:00:00.000Z');
    await storage.writeRestored(key, 'device-value', futureAt);
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': <Map<String, dynamic>>[],
        'serverTime': serverTime.toIso8601String(),
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(await storage.read(key), 'device-value');
    expect(await storage.updatedAt(key), serverTime);
    expect(
      api.putBodies['/user-state/other-income']?['clientUpdatedAt'],
      serverTime.toIso8601String(),
    );
  });

  test('device state wins when server and device timestamps tie', () async {
    final storage = const SecureStorageService();
    final key = UserScopedStorageKeys.otherIncome('user-1');
    final tiedAt = DateTime.parse('2026-07-29T10:00:00.000Z');
    await storage.writeRestored(key, 'device-value', tiedAt);
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': [
          {
            'namespace': 'other-income',
            'payload': 'server-value',
            'deleted': false,
            'clientUpdatedAt': tiedAt.toIso8601String(),
          },
        ],
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(await storage.read(key), 'device-value');
    expect(
      api.putBodies['/user-state/other-income'],
      {
        'payload': 'device-value',
        'clientUpdatedAt': tiedAt.toIso8601String(),
      },
    );
  });

  test('one failed namespace does not stop later durable restores', () async {
    const storage = _OneNamespaceFailingStorage();
    final api = _FakeApi()
      ..getResponses['/user-state'] = {
        'items': [
          {
            'namespace': 'profile-draft',
            'payload': '{"name":"User"}',
            'deleted': false,
            'clientUpdatedAt': '2026-07-29T10:00:00.000Z',
          },
          {
            'namespace': 'paycheck-overrides',
            'payload': '[{"canonicalKey":"basic","amount":80000}]',
            'deleted': false,
            'clientUpdatedAt': '2026-07-29T10:00:00.000Z',
          },
        ],
      };
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );

    await service.restore('user-1');

    expect(
      await storage.read(UserScopedStorageKeys.paycheckOverrides('user-1')),
      '[{"canonicalKey":"basic","amount":80000}]',
    );
  });

  test('durable spend backup retains the complete local transaction data',
      () async {
    final storage = const SecureStorageService();
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: storage,
    );
    final key = UserScopedStorageKeys.spendMap('user-1');
    const value = '{"txns":[{"amount":500,"sender":"BANK","smsId":42,'
        '"bodyPreview":"private text","category":"food"}]}';
    await storage.write(key, value);

    service.scheduleBackup(key, value);
    await service.flushScheduled();

    final payload =
        api.putBodies['/user-state/spend-map']?['payload'] as String;
    expect(payload, value);
  });

  test('oversized durable state is not sent in a retry loop', () async {
    final api = _FakeApi();
    final service = DurableUserStateService(
      auth: _FixedTokenAuthService(),
      api: api,
      storage: const SecureStorageService(),
    );
    final key = UserScopedStorageKeys.spendMap('user-1');
    final value = 'x' * (DurableUserStateService.maxPayloadBytes + 1);

    service.scheduleBackup(key, value);
    await service.flushScheduled();

    expect(api.putBodies, isEmpty);
    expect(
      await const SecureStorageService().read(
        'arth_durable_backup_oversized',
      ),
      isNotNull,
    );
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

    await queue.enqueue('user-1', 'profile', {'version': 1});
    await queue.enqueue('user-1', 'profile', {'version': 2});
    await queue.enqueue('user-1', 'taxResult', {'ok': true});
    await queue.enqueue('user-1', 'invalid', {'bad': true});
    await queue.enqueue(
      'user-1',
      'doneGaps',
      {'blob': 'x' * (SyncQueueService.maxPayloadBytes + 1)},
    );

    final ops = await queue.popAll('user-1');

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

  test('account transition removes the previous in-memory profile', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(userProfileProvider.notifier);

    notifier.update(_sampleProfile());
    notifier.resetForAccount(
      UserAccount(
        uid: 'user-2',
        name: 'Second User',
        email: 'second@example.com',
        createdAt: DateTime(2026, 7, 22),
      ),
    );

    final profile = container.read(userProfileProvider);
    expect(profile.name, 'Second User');
    expect(profile.email, 'second@example.com');
    expect(profile.annualCTC, 0);
    expect(profile.city, isEmpty);
    expect(profile.paysRent, isFalse);
    expect(profile.monthlyRent, 0);
    expect(profile.invested80C, 0);
    expect(profile.hasHomeLoan, isFalse);
  });

  test('cold hydration does not replace cached CTC with remote zero', () {
    const cached = UserProfile(
      name: 'User',
      email: 'user@example.com',
      annualCTC: 1800000,
      city: 'Delhi',
    );
    const remote = UserProfile(
      name: 'User',
      email: 'user@example.com',
      annualCTC: 0,
      city: 'Delhi',
    );

    final resolved = preserveLocalCtcOnHydration(
      remote,
      cached,
      cachedProfileConfirmed: true,
    );

    expect(resolved.annualCTC, 1800000);
    expect(resolved.city, remote.city);
  });

  test('positive remote CTC still replaces an older cached value', () {
    const cached = UserProfile(annualCTC: 1800000);
    const remote = UserProfile(annualCTC: 2000000);

    final resolved = preserveLocalCtcOnHydration(
      remote,
      cached,
      cachedProfileConfirmed: true,
    );

    expect(resolved.annualCTC, 2000000);
  });

  test('cold hydration does not promote an unfinished CTC draft', () {
    const cached = UserProfile(annualCTC: 1800000);
    const remote = UserProfile(annualCTC: 0);

    final resolved = preserveLocalCtcOnHydration(
      remote,
      cached,
      cachedProfileConfirmed: false,
    );

    expect(resolved.annualCTC, 0);
  });
}

class _FakeApi extends ServerApiService {
  final getResponses = <String, Map<String, dynamic>>{};
  final postResponses = <String, Map<String, dynamic>>{};
  final postErrors = <String, ServerApiException>{};
  final postCalls = <String>[];
  final postRetryFlags = <String, bool>{};
  final putBodies = <String, Map<String, dynamic>>{};
  final deleteBodies = <String, Map<String, dynamic>>{};
  final putPaths = <String>[];
  final deletePaths = <String>[];
  ServerApiException? putError;

  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    String? bearerToken,
  }) async {
    return getResponses[path] ?? <String, dynamic>{};
  }

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
    putPaths.add(path);
    putBodies[path] = body ?? <String, dynamic>{};
    final error = putError;
    if (error != null) throw error;
    final clientUpdatedAt = body?['clientUpdatedAt']?.toString();
    return <String, dynamic>{
      'item': {
        'namespace': path.split('/').last,
        'payload': body?['payload'],
        'deleted': false,
        'clientUpdatedAt': clientUpdatedAt,
      },
      'serverTime': clientUpdatedAt,
    };
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    deletePaths.add(path);
    deleteBodies[path] = body ?? <String, dynamic>{};
    final clientUpdatedAt = body?['clientUpdatedAt']?.toString();
    return <String, dynamic>{
      'item': {
        'namespace': path.split('/').last,
        'payload': null,
        'deleted': true,
        'clientUpdatedAt': clientUpdatedAt,
      },
      'serverTime': clientUpdatedAt,
    };
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

  @override
  Future<UserAccount?> loadAccount() async => UserAccount(
        uid: 'user-1',
        name: 'User',
        email: 'user@example.com',
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<AuthenticatedSession?> getValidSession() async =>
      const AuthenticatedSession(
        uid: 'user-1',
        accessToken: 'access-token',
      );
}

class _MissingTokenAuthService extends AuthService {
  @override
  Future<String?> getValidAccessToken() async => null;
}

class _BoundSessionAuthService extends AuthService {
  _BoundSessionAuthService(this.uid);

  final String uid;

  @override
  Future<AuthenticatedSession?> getValidSession() async =>
      AuthenticatedSession(uid: uid, accessToken: 'token-$uid');
}

class _OneNamespaceFailingStorage extends SecureStorageService {
  const _OneNamespaceFailingStorage();

  @override
  Future<void> writeRestored(
    String key,
    String value,
    DateTime updatedAt,
  ) {
    if (key == UserScopedStorageKeys.profile('user-1')) {
      throw StateError('simulated keystore failure');
    }
    return super.writeRestored(key, value, updatedAt);
  }
}

class _RecordingQueue extends SyncQueueService {
  final enqueuedTypes = <String>[];

  @override
  Future<void> enqueue(
    String userId,
    String type,
    Map<String, dynamic> payload,
  ) async {
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
