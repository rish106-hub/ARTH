import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/reconciliation_engine.dart';
import '../engine/money_signal_engine.dart';
import '../models/spend_map.dart';
import '../services/finance_message_parser.dart';
import '../services/secure_storage_service.dart';
import '../services/user_scoped_storage.dart';
import '../services/sms_reader_service.dart';
import '../services/spend_map_service.dart';
import '../features/spend_completeness/providers/spend_completeness_provider.dart';
import 'auth_provider.dart';
import 'other_income_provider.dart';
import 'paycheck_provider.dart';
import 'spend_map_adjustments_provider.dart';
import 'tax_document_provider.dart';
import 'user_profile_provider.dart';

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

String _spendMapKey(String uid) => UserScopedStorageKeys.spendMap(uid);

class SpendMapState {
  const SpendMapState({
    this.map,
    this.loading = false,
    this.permissionDenied = false,
    this.selectedPeriod = SpendScanPeriod.threeMonths,
    this.error,
    this.awaitingOtherIncomeAnswer = false,
    this.showRecalculationNotice = false,
  });

  final SpendMap? map;
  final bool loading;
  final bool permissionDenied;
  final SpendScanPeriod selectedPeriod;
  final String? error;

  /// True right after SMS permission is granted for the first time, until the
  /// user answers the one-time "any other income to add?" question. The UI
  /// shows the follow-up prompt while this is true and the actual SMS read
  /// is held until [SpendMapNotifier.resumeScanAfterOtherIncomeAnswer] runs.
  final bool awaitingOtherIncomeAnswer;
  final bool showRecalculationNotice;

  bool get hasData => map != null && !map!.isEmpty;

  SpendMapState copyWith({
    SpendMap? map,
    bool? loading,
    bool? permissionDenied,
    SpendScanPeriod? selectedPeriod,
    Object? error = _unset,
    bool? awaitingOtherIncomeAnswer,
    bool? showRecalculationNotice,
  }) {
    return SpendMapState(
      map: map ?? this.map,
      loading: loading ?? this.loading,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      error: identical(error, _unset) ? this.error : error as String?,
      awaitingOtherIncomeAnswer:
          awaitingOtherIncomeAnswer ?? this.awaitingOtherIncomeAnswer,
      showRecalculationNotice:
          showRecalculationNotice ?? this.showRecalculationNotice,
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

  SpendScanPeriod? _pendingPeriod;

  @override
  SpendMapState build() {
    Future.microtask(_loadCached);
    // Income falls back to payslip/CTC when no salary credit is detected in
    // SMS; re-derive it whenever a document, paycheck, or profile changes.
    ref.listen(paycheckProvider, (_, __) => _refreshUserContext());
    ref.listen(payslipTaxPrefillProvider, (_, __) => _refreshUserContext());
    ref.listen(
      userProfileProvider.select((p) => p.annualCTC),
      (_, __) => _refreshUserContext(),
    );
    // Other-income total (user-entered, local-only) also feeds the figures
    // shown on screen — re-derive whenever the user adds/removes a source.
    ref.listen(otherIncomeProvider, (_, __) => _refreshUserContext());
    ref.listen(spendMapAdjustmentsProvider, (_, __) => _refreshUserContext());
    ref.listen(spendCompletenessProvider, (_, __) => _refreshUserContext());
    return const SpendMapState();
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  /// Take-home income (rupees/month) from confirmed documents, used only when
  /// SMS carries no detectable salary credit: net pay → payslip gross → CTC.
  int? _fallbackMonthlyIncome() {
    final net = ref.read(paycheckProvider).netCredited;
    if (net > 0) return net;
    final gross = ref.read(payslipTaxPrefillProvider)?.annualGrossSalary;
    if (gross != null && gross > 0) return (gross / 12).round();
    final ctc = ref.read(userProfileProvider).annualCTC;
    if (ctc > 0) return (ctc / 12).round();
    return null;
  }

  /// Applies transient income adjustments (payslip/CTC fallback, other income,
  /// and user-edited income/spend overrides) in one place.
  SpendMap _applyUserContext(SpendMap map) {
    final otherIncome = ref.read(otherIncomeProvider.notifier).totalMonthly;
    final adjustments = ref.read(spendMapAdjustmentsProvider);
    final completeness = ref.read(spendCompletenessProvider);
    final paycheck = ref.read(paycheckProvider);
    final profile = ref.read(userProfileProvider);
    final contextual = map
        .withFallbackIncome(_fallbackMonthlyIncome())
        .withOtherIncome(otherIncome)
        .withAdjustments(
          manualPrimaryMonthlyIncome: adjustments.manualPrimaryMonthlyIncome,
          manualMonthlySpend: adjustments.manualMonthlySpend,
        )
        .withTrustedSalarySource(completeness.trustedSalarySourceId);
    final signal = MoneySignalEngine.resolveIncome(
      editedMonthlyIncome: adjustments.manualPrimaryMonthlyIncome,
      confirmedPayslipNet:
          paycheck.grossReceived > 0 ? paycheck.netCredited : 0,
      confirmedPayslipGross:
          paycheck.grossReceived > 0 && paycheck.netCredited <= 0
              ? paycheck.grossReceived
              : 0,
      trustedSalarySmsMonthly: contextual.salaryCredited > 0
          ? contextual.observedPrimaryMonthlyIncome
          : 0,
      annualCtc: profile.annualCTC,
      otherMonthlyIncome: otherIncome,
    );
    return contextual.withIncomeSignal(signal);
  }

  void _refreshUserContext() {
    final map = state.map;
    if (map == null) return;
    state = state.copyWith(map: _applyUserContext(map));
    _bridgeSalarySms(state.map);
  }

  void _bridgeSalarySms(SpendMap? map) {
    ref.read(paycheckProvider.notifier).syncSalarySms(
          map == null ? const SalarySmsSnapshot() : salarySmsFromSpendMap(map),
        );
  }

  Future<void> _loadCached() async {
    final uid = _uid();
    final json = await _storage.read(_spendMapKey(uid));
    if (json == null) return;
    try {
      state = state.copyWith(
        map: _applyUserContext(SpendMap.fromJsonString(json)),
        showRecalculationNotice: await _storage.read(
              UserScopedStorageKeys.spendMapRecalculationNotice(uid),
            ) !=
            'seen',
      );
      _bridgeSalarySms(state.map);
    } catch (_) {
      // Corrupt cache — ignore, a rescan will overwrite it.
    }
  }

  /// Requests SMS permission (if needed) and, once granted for the first
  /// time, pauses before actually reading the inbox so the UI can ask the
  /// one-time "any other income?" question — see [resumeScanAfterOtherIncomeAnswer].
  /// Returning users who already answered skip straight to the real scan.
  Future<void> scan([SpendScanPeriod? period]) async {
    // Re-entrancy guard: ignore taps while a scan is already running.
    if (state.loading) return;
    final selected = period ?? state.selectedPeriod;
    state = state.copyWith(
      loading: true,
      permissionDenied: false,
      selectedPeriod: selected,
      error: null,
    );
    try {
      if (!_reader.isSupported) {
        state = state.copyWith(
          loading: false,
          error: 'SMS scanning is available on Android only.',
        );
        return;
      }
      final granted = await _reader.requestPermission();
      if (!granted) {
        state = state.copyWith(loading: false, permissionDenied: true);
        return;
      }

      final alreadyAsked = ref.read(otherIncomeProvider.notifier).hasAsked;
      if (!alreadyAsked) {
        _pendingPeriod = selected;
        state = state.copyWith(
          loading: false,
          awaitingOtherIncomeAnswer: true,
        );
        return;
      }

      await _performScan(selected);
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// Called once the follow-up "any other income?" question has been
  /// answered (either way) — proceeds with the SMS read that [scan] paused.
  Future<void> resumeScanAfterOtherIncomeAnswer() async {
    final period = _pendingPeriod ?? state.selectedPeriod;
    _pendingPeriod = null;
    state = state.copyWith(loading: true, awaitingOtherIncomeAnswer: false);
    try {
      await _performScan(period);
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// Reads the inbox, parses on-device, builds and persists the spend map,
  /// runs the AI categorization fallback, and best-effort syncs a summary.
  /// Assumes SMS permission is already granted.
  Future<void> _performScan(SpendScanPeriod selected) async {
    final since = selected.since(DateTime.now());
    final raw = await _reader.readInbox(since: since);
    final txns = _parser.parseAll(raw);

    final map = _buildMap(txns, since);
    await _storage.write(_spendMapKey(_uid()), map.toJsonString());
    state = state.copyWith(
      map: _applyUserContext(map),
      loading: false,
    );
    _bridgeSalarySms(state.map);

    // Hybrid pass: refine the transactions the on-device rules left as
    // `other` using the AI fallback. Best-effort — the rules result already
    // shows; this only upgrades categories when it succeeds.
    final enriched = await _enrichCategoriesWithAi(map);
    final finalMap = enriched ?? map;

    // Best-effort remote mirror; never blocks or fails the local flow.
    try {
      await _sync.push(finalMap);
    } catch (_) {}
  }

  /// Changes the scan window. If a map already exists, immediately re-scans so
  /// the figures reflect the new window (the period chips are otherwise inert).
  /// Before the first scan we only record the choice and wait for the explicit
  /// scan the empty-state button triggers.
  Future<void> selectPeriod(SpendScanPeriod period) async {
    if (period == state.selectedPeriod) return;
    state = state.copyWith(selectedPeriod: period);
    if (state.hasData) await scan(period);
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
      categorySource: CategorySource.manual,
    );
    final updated = SpendMap(
      txns: txns,
      windowStart: current.windowStart,
      windowEnd: current.windowEnd,
      generatedAt: DateTime.now(),
    );
    await _storage.write(_spendMapKey(_uid()), updated.toJsonString());
    state = state.copyWith(map: _applyUserContext(updated));
    _bridgeSalarySms(state.map);
    try {
      await _sync.push(updated);
    } catch (_) {}
  }

  // Runs of 5+ digits (account/card numbers, phone numbers) stripped before any
  // text leaves the device.
  static final RegExp _longDigitRun = RegExp(r'\d{5,}');
  // Currency amounts (Rs/INR/₹ 1,234.56). Not needed to categorize, so dropped.
  static final RegExp _amountToken = RegExp(
      r'(?:rs\.?|inr|₹)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?',
      caseSensitive: false);

  /// Builds the minimal text sent to the AI — only what categorization needs.
  /// Prefers the merchant/payee alone (nothing else leaves the device); falls
  /// back to the SMS body only when no merchant was extracted, and even then
  /// strips amounts and long digit runs.
  static String _redactForAi(FinanceTxn txn) {
    final merchant = txn.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    final body = txn.bodyPreview ?? '';
    return body
        .replaceAll(_amountToken, '')
        .replaceAll(_longDigitRun, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Sends the still-`other` debit transactions to the AI fallback and merges
  /// back any confident category/merchant. Returns an updated, persisted map,
  /// or null when nothing changed (no candidates, signed out, AI unavailable).
  Future<SpendMap?> _enrichCategoriesWithAi(SpendMap map) async {
    // Only debits the rules could not place, that the user has not already
    // corrected by hand.
    final candidates = <int>[];
    for (var i = 0; i < map.txns.length; i++) {
      final t = map.txns[i];
      if (t.direction == TxnDirection.debit &&
          t.category == SpendCategory.other &&
          t.categorySource == CategorySource.rules) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return null;

    // Build minimal redacted items; drop any with nothing useful left to send.
    // Cap per request; the backend also enforces a max.
    final items = <({String id, String text})>[];
    for (final i in candidates) {
      final text = _redactForAi(map.txns[i]);
      if (text.isEmpty) continue;
      items.add((id: i.toString(), text: text));
      if (items.length >= 40) break;
    }
    if (items.isEmpty) return null;

    final guesses = await _sync.categorize(items);
    if (guesses.isEmpty) return null;

    final txns = [...map.txns];
    var changed = false;
    guesses.forEach((id, guess) {
      final index = int.tryParse(id);
      if (index == null || index < 0 || index >= txns.length) return;
      if (guess.confidence == 'low') return; // keep 'other' when unsure
      if (!SpendCategory.all.contains(guess.category)) return;
      txns[index] = txns[index].copyWith(
        category: guess.category,
        merchant: guess.merchant?.isNotEmpty == true ? guess.merchant : null,
        categorySource: CategorySource.ai,
      );
      changed = true;
    });
    if (!changed) return null;

    final updated = SpendMap(
      txns: txns,
      windowStart: map.windowStart,
      windowEnd: map.windowEnd,
      generatedAt: map.generatedAt,
    );
    await _storage.write(_spendMapKey(_uid()), updated.toJsonString());
    state = state.copyWith(map: _applyUserContext(updated));
    _bridgeSalarySms(state.map);
    return updated;
  }

  SpendMap _buildMap(List<FinanceTxn> txns, DateTime since) {
    // Window reflects the requested scan period, not the transaction extent, so
    // it stays truthful even when data is sparse. Monthly averages are derived
    // from the months each series actually covers (see SpendMap), not from this
    // window, so a partial window no longer distorts them.
    final now = DateTime.now();
    return SpendMap(
      txns: txns,
      windowStart: since,
      windowEnd: now,
      generatedAt: now,
    );
  }

  Future<void> clear() async {
    final uid = _uid();
    if (uid != 'guest') {
      await _storage.delete(_spendMapKey(uid));
    }
    state = const SpendMapState();
    _bridgeSalarySms(null);
  }

  Future<void> clearLocalData() => clear();

  Future<void> dismissRecalculationNotice() async {
    await _storage.write(
      UserScopedStorageKeys.spendMapRecalculationNotice(_uid()),
      'seen',
    );
    state = state.copyWith(showRecalculationNotice: false);
  }
}

final spendMapProvider =
    NotifierProvider<SpendMapNotifier, SpendMapState>(SpendMapNotifier.new);
