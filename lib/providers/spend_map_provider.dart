import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/spend_map.dart';
import '../services/finance_message_parser.dart';
import '../services/secure_storage_service.dart';
import '../services/sms_reader_service.dart';
import '../services/spend_map_service.dart';
import 'auth_provider.dart';

enum SpendScanPeriod {
  oneMonth,
  threeMonths,
  sixMonths,
  twelveMonths,
  yearToDate,
}

extension SpendScanPeriodLabel on SpendScanPeriod {
  String get label => switch (this) {
        SpendScanPeriod.oneMonth => '1 month',
        SpendScanPeriod.threeMonths => '3 months',
        SpendScanPeriod.sixMonths => '6 months',
        SpendScanPeriod.twelveMonths => '12 months',
        SpendScanPeriod.yearToDate => 'YTD',
      };

  DateTime since(DateTime now) => switch (this) {
        SpendScanPeriod.oneMonth => DateTime(now.year, now.month - 1),
        SpendScanPeriod.threeMonths => DateTime(now.year, now.month - 3),
        SpendScanPeriod.sixMonths => DateTime(now.year, now.month - 6),
        SpendScanPeriod.twelveMonths => DateTime(now.year, now.month - 12),
        SpendScanPeriod.yearToDate => DateTime(now.year),
      };
}

String _spendMapKey(String uid) => 'arth_spend_map_$uid';

class SpendMapState {
  const SpendMapState({
    this.map,
    this.loading = false,
    this.permissionDenied = false,
    this.selectedPeriod = SpendScanPeriod.threeMonths,
    this.error,
  });

  final SpendMap? map;
  final bool loading;
  final bool permissionDenied;
  final SpendScanPeriod selectedPeriod;
  final String? error;

  bool get hasData => map != null && !map!.isEmpty;

  SpendMapState copyWith({
    SpendMap? map,
    bool? loading,
    bool? permissionDenied,
    SpendScanPeriod? selectedPeriod,
    Object? error = _unset,
  }) {
    return SpendMapState(
      map: map ?? this.map,
      loading: loading ?? this.loading,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
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

  // Test seams.
  void debugInjectDependencies({
    SmsReaderService? reader,
    SpendMapService? sync,
  }) {
    if (reader != null) _reader = reader;
    if (sync != null) _sync = sync;
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
  Future<void> scan([SpendScanPeriod? period]) async {
    final selected = period ?? state.selectedPeriod;
    state = state.copyWith(
      loading: true,
      permissionDenied: false,
      selectedPeriod: selected,
      error: null,
    );
    try {
      final granted = await _reader.requestPermission();
      if (!granted) {
        state = state.copyWith(loading: false, permissionDenied: true);
        return;
      }

      final since = selected.since(DateTime.now());
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

  void selectPeriod(SpendScanPeriod period) {
    state = state.copyWith(selectedPeriod: period);
  }

  Future<void> recategorize(int transactionIndex, String category) async {
    final current = state.map;
    if (current == null ||
        transactionIndex < 0 ||
        transactionIndex >= current.txns.length ||
        !SpendCategory.all.contains(category)) {
      return;
    }
    final txns = [...current.txns];
    txns[transactionIndex] = txns[transactionIndex].copyWith(
      category: category,
    );
    final updated = SpendMap(
      txns: txns,
      windowStart: current.windowStart,
      windowEnd: current.windowEnd,
      generatedAt: DateTime.now(),
    );
    await _storage.write(_spendMapKey(_uid()), updated.toJsonString());
    state = state.copyWith(map: updated);
    try {
      await _sync.push(updated);
    } catch (_) {}
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
    var earliest = txns.first.date;
    var latest = txns.first.date;
    for (final t in txns) {
      if (t.date.isBefore(earliest)) earliest = t.date;
      if (t.date.isAfter(latest)) latest = t.date;
    }
    return SpendMap(
      txns: txns,
      windowStart: earliest,
      windowEnd: latest,
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
