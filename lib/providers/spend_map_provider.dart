import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/spend_map.dart';
import '../services/auth_service.dart';
import '../services/finance_message_parser.dart';
import '../services/gmail_service.dart';
import '../services/secure_storage_service.dart';
import '../services/sms_reader_service.dart';
import '../services/spend_map_service.dart';
import 'auth_provider.dart';

/// How far back to scan the SMS inbox.
const Duration kSpendScanWindow = Duration(days: 120);

String _spendMapKey(String uid) => 'arth_spend_map_$uid';

class SpendMapState {
  const SpendMapState({
    this.map,
    this.loading = false,
    this.permissionDenied = false,
    this.error,
  });

  final SpendMap? map;
  final bool loading;
  final bool permissionDenied;
  final String? error;

  bool get hasData => map != null && !map!.isEmpty;

  SpendMapState copyWith({
    SpendMap? map,
    bool? loading,
    bool? permissionDenied,
    Object? error = _unset,
  }) {
    return SpendMapState(
      map: map ?? this.map,
      loading: loading ?? this.loading,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  static const _unset = Object();
}

class SpendMapNotifier extends Notifier<SpendMapState> {
  final _storage = const SecureStorageService();
  final _parser = const FinanceMessageParser();
  SmsReaderService _reader = SmsReaderService();
  SpendMapService _sync = SpendMapService();
  GmailService _gmail = GmailService();
  AuthService _auth = AuthService();

  // Test seams.
  void debugInjectDependencies({
    SmsReaderService? reader,
    SpendMapService? sync,
    GmailService? gmail,
    AuthService? auth,
  }) {
    if (reader != null) _reader = reader;
    if (sync != null) _sync = sync;
    if (gmail != null) _gmail = gmail;
    if (auth != null) _auth = auth;
  }

  @override
  SpendMapState build() {
    Future.microtask(_loadCached);
    return const SpendMapState();
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  Future<void> _loadCached() async {
    final json = await _storage.read(_spendMapKey(_uid()));
    if (json == null) return;
    try {
      state = state.copyWith(map: SpendMap.fromJsonString(json));
    } catch (_) {
      // Corrupt cache — ignore, a rescan will overwrite it.
    }
  }

  /// Requests SMS permission (if needed), reads the inbox, parses on-device,
  /// builds and persists the spend map, and best-effort syncs a summary.
  Future<void> scan() async {
    state = state.copyWith(loading: true, permissionDenied: false, error: null);
    try {
      final granted = await _reader.requestPermission();
      if (!granted) {
        state = state.copyWith(loading: false, permissionDenied: true);
        return;
      }

      final since = DateTime.now().subtract(kSpendScanWindow);
      final raw = await _reader.readInbox(since: since);
      final txns = _parser.parseAll(raw);

      final map = _buildMap(txns, since);
      await _storage.write(_spendMapKey(_uid()), map.toJsonString());
      state = state.copyWith(map: map, loading: false);

      // Best-effort remote mirror; never blocks or fails the local flow.
      try {
        await _sync.push(map);
      } catch (_) {}
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// Authorizes Gmail (readonly), fetches invoice/receipt emails, parses them
  /// on-device and merges the spends into the existing map (deduped against
  /// SMS). Requires the gmail.readonly scope to be configured for the app.
  Future<void> connectGmail() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final token = await _auth.authorizeGmailReadonly();
      if (token == null || token.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'Gmail authorization was cancelled or failed.',
        );
        return;
      }

      final emails = await _gmail.fetchInvoices(accessToken: token);
      final emailTxns = <FinanceTxn>[];
      for (final e in emails) {
        final txn = _parser.parseEmailInvoice(
          from: e.from,
          subject: e.subject,
          snippet: e.snippet,
          date: e.date,
        );
        if (txn != null) emailTxns.add(txn);
      }

      final existing = state.map?.txns ?? const <FinanceTxn>[];
      final merged = _mergeDedupe(existing, emailTxns);
      final since = DateTime.now().subtract(kSpendScanWindow);
      final map = _buildMap(merged, since);

      await _storage.write(_spendMapKey(_uid()), map.toJsonString());
      state = state.copyWith(map: map, loading: false);

      try {
        await _sync.push(map);
      } catch (_) {}
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// Adds email txns that don't duplicate an existing spend (same rounded
  /// amount within 2 days).
  List<FinanceTxn> _mergeDedupe(
    List<FinanceTxn> existing,
    List<FinanceTxn> incoming,
  ) {
    final result = List<FinanceTxn>.from(existing);
    for (final txn in incoming) {
      final duplicate = existing.any((e) =>
          e.amount == txn.amount &&
          e.direction == txn.direction &&
          e.date.difference(txn.date).inDays.abs() <= 2);
      if (!duplicate) result.add(txn);
    }
    return result;
  }

  SpendMap _buildMap(List<FinanceTxn> txns, DateTime since) {
    final now = DateTime.now();
    if (txns.isEmpty) {
      return SpendMap(
        txns: const [],
        windowStart: since,
        windowEnd: now,
        generatedAt: now,
      );
    }
    final dates = txns.map((t) => t.date).toList()..sort();
    return SpendMap(
      txns: txns,
      windowStart: dates.first,
      windowEnd: dates.last,
      generatedAt: now,
    );
  }

  Future<void> clear() async {
    await _storage.delete(_spendMapKey(_uid()));
    state = const SpendMapState();
  }
}

final spendMapProvider =
    NotifierProvider<SpendMapNotifier, SpendMapState>(SpendMapNotifier.new);
