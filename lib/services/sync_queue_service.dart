import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

/// A single operation that failed to reach the server and needs to be retried.
class PendingOp {
  final String type; // 'profile' | 'taxResult' | 'doneGaps'
  final Map<String, dynamic> payload;
  final int enqueuedAt; // epoch ms

  const PendingOp({
    required this.type,
    required this.payload,
    required this.enqueuedAt,
  });

  factory PendingOp.fromJson(Map<String, dynamic> json) => PendingOp(
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        enqueuedAt: json['enqueuedAt'] as int,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
        'enqueuedAt': enqueuedAt,
      };
}

/// Persists failed sync operations in encrypted device storage so they survive
/// app restarts and are replayed the next time the user has a live session.
///
/// Deduplication: only the latest operation of each type is kept.
/// There is no point retrying an old profile write when a newer one exists.
class SyncQueueService {
  static const _key = 'arth_sync_queue';
  static const maxQueueItems = 10;
  static const maxPayloadBytes = 64 * 1024;
  static const _allowedTypes = {'profile', 'taxResult', 'doneGaps'};

  final SecureStorageService _storage;

  const SyncQueueService({SecureStorageService? storage})
      : _storage = storage ?? const SecureStorageService();

  Future<List<PendingOp>> _read() async {
    try {
      final raw = await _storage.read(_key, migrateFromPrefs: true);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PendingOp.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      if (kDebugMode) debugPrint('[SyncQueue] read error');
      return [];
    }
  }

  Future<void> _write(List<PendingOp> ops) async {
    try {
      if (ops.isEmpty) {
        await _storage.delete(_key);
      } else {
        await _storage.write(
          _key,
          jsonEncode(ops.map((o) => o.toJson()).toList()),
        );
      }
    } catch (_) {
      if (kDebugMode) debugPrint('[SyncQueue] write error');
    }
  }

  /// Enqueue or replace an operation.
  /// Only the latest payload for each type is retained.
  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    if (!_allowedTypes.contains(type)) return;
    final encodedPayload = jsonEncode(payload);
    if (utf8.encode(encodedPayload).length > maxPayloadBytes) {
      if (kDebugMode) debugPrint('[SyncQueue] dropped oversized op: $type');
      return;
    }

    final ops = await _read();
    ops.removeWhere((o) => o.type == type); // deduplicate
    ops.add(
      PendingOp(
        type: type,
        payload: payload,
        enqueuedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (ops.length > maxQueueItems) {
      ops.removeRange(0, ops.length - maxQueueItems);
    }
    await _write(ops);
    if (kDebugMode) {
      debugPrint('[SyncQueue] enqueued: $type (queue size: ${ops.length})');
    }
  }

  /// Remove and return all pending ops. The caller is responsible for
  /// re-enqueueing any that still fail.
  Future<List<PendingOp>> popAll() async {
    final ops = await _read();
    await _write([]);
    return ops;
  }

  Future<void> clear() => _write([]);

  Future<bool> get hasItems async => (await _read()).isNotEmpty;
}
