import 'package:flutter/foundation.dart';

import '../models/tax_result.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'server_api_service.dart';
import 'sync_queue_service.dart';

/// Wraps all server write operations with:
///  1. Automatic retry  — up to 3 attempts with exponential back-off
///     (500 ms → 1 s → 2 s).  4xx errors are not retried because they
///     indicate a bad request that won't improve with repetition.
///  2. Persistent queue — if all retry attempts fail the operation is
///     persisted via encrypted [SyncQueueService] storage and replayed
///     the next time [flushPendingQueue] is called (i.e. on the next
///     successful startup with a live session).
class BackendSyncService {
  final ServerApiService _api;
  final AuthService _auth;
  final SyncQueueService _queue;

  BackendSyncService({
    ServerApiService? api,
    AuthService? auth,
    SyncQueueService? queue,
  })  : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService(),
        _queue = queue ?? const SyncQueueService();

  // ─── PUBLIC API ─────────────────────────────────────────────────────────────
  // Each public sync method retries internally and, on final failure,
  // enqueues the operation so it is not lost.

  /// Deletes all user data (profile, tax results, done-gaps) from the server.
  Future<void> deleteAllData() async {
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return;
      await _api.delete('/profile', bearerToken: token);
    } catch (_) {
      debugPrint('[BackendSyncService] deleteAllData failed');
    }
  }

  Future<bool> syncProfile(UserProfile profile) async {
    try {
      await _putProfile(profile);
      return true;
    } catch (error) {
      if (!_shouldQueue(error)) return false;
      await _queue.enqueue('profile', profile.toJson());
      return false;
    }
  }

  Future<UserProfile?> fetchProfile() async {
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return null;
      final response = await _api.getJson('/profile', bearerToken: token);
      final data = response['profile'];
      if (data is! Map<String, dynamic>) return null;
      return UserProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> syncTaxResult(TaxResult result) async {
    try {
      await _putTaxResult(result);
    } catch (error) {
      if (!_shouldQueue(error)) return;
      await _queue.enqueue('taxResult', result.toJson());
    }
  }

  Future<TaxResult?> fetchTaxResult() async {
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return null;
      final response = await _api.getJson(
        '/tax-results/current',
        bearerToken: token,
      );
      final data = response['taxResult'];
      if (data is! Map<String, dynamic>) return null;
      return TaxResult.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> syncDoneGaps(Set<String> gapIds) async {
    try {
      await _putDoneGaps(gapIds);
    } catch (error) {
      if (!_shouldQueue(error)) return;
      await _queue.enqueue('doneGaps', {'gapIds': gapIds.toList()});
    }
  }

  Future<Set<String>> fetchDoneGaps() async {
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return {};
      final response = await _api.getJson(
        '/done-gaps/current',
        bearerToken: token,
      );
      final ids = response['gapIds'] as List<dynamic>? ?? const [];
      return ids.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> trackEvent({
    required String name,
    Map<String, dynamic>? metadata,
  }) async {
    // Events are analytics-only — silently skipped on failure, not queued.
    try {
      final token = await _auth.getValidAccessToken();
      if (token == null) return;
      await _withRetry(
        () => _api.postNoContent(
          '/events',
          bearerToken: token,
          body: {'name': name, 'metadata': metadata ?? <String, dynamic>{}},
        ),
      );
    } catch (_) {}
  }

  // ─── QUEUE FLUSH ────────────────────────────────────────────────────────────

  /// Replays any operations that failed in previous sessions.
  /// Should be called once after a successful authenticated startup.
  ///
  /// Uses the internal _putX methods directly so failures are caught here
  /// rather than re-enqueued in a loop. Anything that still fails is
  /// put back in the queue for the next session.
  Future<void> flushPendingQueue() async {
    final ops = await _queue.popAll();
    if (ops.isEmpty) return;

    if (kDebugMode) {
      debugPrint('[SyncQueue] flushing ${ops.length} pending op(s)');
    }

    final failed = <PendingOp>[];
    for (final op in ops) {
      try {
        switch (op.type) {
          case 'profile':
            await _putProfile(UserProfile.fromJson(op.payload));
          case 'taxResult':
            await _putTaxResult(TaxResult.fromJson(op.payload));
          case 'doneGaps':
            final ids = (op.payload['gapIds'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toSet();
            await _putDoneGaps(ids);
        }
        if (kDebugMode) debugPrint('[SyncQueue] flushed: ${op.type}');
      } catch (error) {
        if (!_shouldQueue(error)) continue;
        // Still failing — put it back.
        failed.add(op);
        if (kDebugMode) debugPrint('[SyncQueue] still pending: ${op.type}');
      }
    }

    for (final op in failed) {
      await _queue.enqueue(op.type, op.payload);
    }
  }

  // ─── INTERNAL PUT METHODS ───────────────────────────────────────────────────
  // These retry but throw on final failure. They are used both by the public
  // sync methods (which catch + enqueue) and by flushPendingQueue (which
  // catches + re-enqueues only if still failing).

  Future<void> _putProfile(UserProfile profile) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('no auth token');
    await _withRetry(
      () =>
          _api.putJson('/profile', bearerToken: token, body: profile.toJson()),
    );
  }

  Future<void> _putTaxResult(TaxResult result) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('no auth token');
    await _withRetry(
      () => _api.putJson(
        '/tax-results/current',
        bearerToken: token,
        body: result.toJson(),
      ),
    );
  }

  Future<void> _putDoneGaps(Set<String> gapIds) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('no auth token');
    await _withRetry(
      () => _api.putJson(
        '/done-gaps/current',
        bearerToken: token,
        body: {'gapIds': gapIds.toList()},
      ),
    );
  }

  // ─── RETRY HELPER ───────────────────────────────────────────────────────────

  /// Runs [fn] up to [maxAttempts] times.
  ///
  /// Back-off schedule (between attempts):
  ///   attempt 1 → 2 : 500 ms
  ///   attempt 2 → 3 : 1 000 ms
  ///   attempt 3 → 4 : 2 000 ms  (if maxAttempts > 3)
  ///
  /// 4xx responses are not retried — they indicate the request itself is
  /// invalid and repeating it will not help.
  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } on ServerApiException catch (e) {
        // Client error — retrying will not fix it.
        if (e.statusCode >= 400 && e.statusCode < 500) rethrow;
        if (attempt == maxAttempts) rethrow;
      } catch (_) {
        if (attempt == maxAttempts) rethrow;
      }
      // Exponential back-off: 500 ms, 1 000 ms, 2 000 ms, …
      await Future.delayed(Duration(milliseconds: 500 * (1 << (attempt - 1))));
    }
    // Unreachable — the loop always rethrows on the final attempt.
    throw StateError('unreachable');
  }

  bool _shouldQueue(Object error) {
    if (error is StateError && error.message == 'no auth token') {
      return false;
    }
    return error is! ServerApiException || error.statusCode >= 500;
  }
}
