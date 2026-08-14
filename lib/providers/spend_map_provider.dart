import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/reconciliation_engine.dart';
import '../engine/money_signal_engine.dart';
import '../models/spend_map.dart';
import '../services/finance_message_parser.dart';
import '../services/merchant_category_rules.dart';
import '../services/secure_storage_service.dart';
import '../services/card_spend_integrity.dart';
import '../services/transfer_correlator.dart';
import '../services/user_scoped_storage.dart';
import '../services/sms_reader_service.dart';
import '../services/spend_map_service.dart';
import '../features/accounts/providers/account_registry_provider.dart';
import '../features/spend_completeness/engine/spend_completeness_engine.dart';
import '../features/spend_completeness/providers/spend_completeness_provider.dart';
import 'analytics_provider.dart';
import 'auth_provider.dart';
import 'custom_spend_categories_provider.dart';
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
    Duration? liveScanDebounce,
  }) {
    if (liveScanDebounce != null) _liveScanDebounce = liveScanDebounce;
    if (sync != null) _sync = sync;
    if (reader != null) {
      _reader = reader;
      // build() already registered a listener on the previous reader. Register
      // again so the injected one is what drives live updates.
      _listenForNewSms();
    }
  }

  SpendScanPeriod? _pendingPeriod;

  /// Merchant → category rules taught by the user's manual corrections. These
  /// always win: the user is the authority on their own spending.
  MerchantCategoryRules _categoryRules = const MerchantCategoryRules.empty();

  /// Payees a previous AI pass already resolved. Consulted before deciding what
  /// to send, so a payee is never paid for twice — the shared budget is a fixed
  /// total across all users, not an allowance per scan.
  MerchantCategoryRules _aiMemory = const MerchantCategoryRules.empty();
  bool _categoryMemoryLoaded = false;

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
    _listenForNewSms();
    ref.onDispose(() => _liveScanTimer?.cancel());
    return const SpendMapState();
  }

  Timer? _liveScanTimer;
  Duration _liveScanDebounce = const Duration(seconds: 3);

  /// A salary credit or a spend alert arriving while the app is open used to sit
  /// there until the user pulled a manual rescan, which made the map look stale
  /// exactly when it mattered most.
  ///
  /// The new message is not parsed and grafted on directly. It re-runs the
  /// normal scan, so correlation, ownership inference, card-bill integrity and
  /// the category memory all apply to it — a second ingestion path would drift
  /// from those rules the first time one of them changed.
  void _listenForNewSms() {
    _reader.listenForNewSms((_) {
      // Banks often send two alerts for one payment a second apart. Debouncing
      // collapses that burst into a single scan.
      _liveScanTimer?.cancel();
      _liveScanTimer = Timer(_liveScanDebounce, () {
        // Only refresh a map the user has already built. Arriving SMS is not a
        // reason to start scanning on someone who never asked for it.
        if (state.map == null || state.loading) return;
        _performScan(state.selectedPeriod).ignore();
      });
    });
  }

  /// Catches up on anything that arrived while the app was backgrounded or shut,
  /// where the foreground listener could not fire. Cheap when nothing changed:
  /// the scan is bounded by the selected window.
  Future<void> refreshIfStale() async {
    if (state.map == null || state.loading) return;
    if (!_reader.isSupported) return;
    await _performScan(state.selectedPeriod);
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

  /// Loads both merchant memories once per session. Called from the cache load
  /// and the scan path, because a first-run scan can start before (or without)
  /// any cached map being read.
  Future<void> _ensureCategoryMemoryLoaded() async {
    if (_categoryMemoryLoaded) return;
    _categoryMemoryLoaded = true;
    final uid = _uid();
    _categoryRules = MerchantCategoryRules.fromJsonString(
      await _storage.read(UserScopedStorageKeys.spendCategoryRules(uid)),
    );
    _aiMemory = MerchantCategoryRules.fromJsonString(
      await _storage.read(UserScopedStorageKeys.spendCategoryAiMemory(uid)),
    );
  }

  Future<void> _loadCached() async {
    final uid = _uid();
    await _ensureCategoryMemoryLoaded();
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
        state = state.copyWith(loading: false, awaitingOtherIncomeAnswer: true);
        return;
      }

      await _performScan(selected);
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
      await ref.read(analyticsProvider).smsScanFailed(selected.name);
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
    // Logged here rather than in [scan] so a started event means the read
    // actually began — not that a tap was refused for platform or permission.
    await ref.read(analyticsProvider).smsScanStarted(selected.name);
    await _ensureCategoryMemoryLoaded();
    final since = selected.since(DateTime.now());
    final previous = state.map;
    final raw = await _reader.readInbox(since: since);
    final txns = _applyUserSalarySenders(
      _applyKnownCategories(_parser.parseAll(raw), previous),
    );

    // Learn which accounts and cards these messages are about before anything
    // reads the map. Ownership is what lets a movement between the user's own
    // accounts be recognised as a transfer rather than as spending.
    final registry = ref.read(accountRegistryProvider.notifier);
    await registry.observe(txns);

    // Correlate again now that ownership is known. parseAll already applied the
    // reference rule, which needs no registry; this pass adds the endpoint rule,
    // which catches the transfers where a bank quoted no reference at all.
    final correlated = const TransferCorrelator().correlate(
      txns,
      owns: registry.owns,
    );

    // Last: keep a card's spending visible when the issuer never itemised it.
    // Runs after correlation so it can see which bills were classed as internal.
    final reconciled = const CardSpendIntegrity().apply(correlated);

    // Balances come from the same messages, but are read separately: a stated
    // balance is a position, not a movement, and the message that carries it is
    // usually also reporting a payment that is already counted.
    final map =
        _buildMap(reconciled, since).withBalances(_parser.parseBalances(raw));
    await _storage.write(_spendMapKey(_uid()), map.toJsonString());
    state = state.copyWith(map: _applyUserContext(map), loading: false);
    _bridgeSalarySms(state.map);
    // Completed once the map the user can act on exists. The AI category pass
    // below only upgrades labels, so waiting for it would under-report success.
    await ref.read(analyticsProvider).smsScanCompleted(
          periodLabel: selected.name,
          transactionCount: map.txns.length,
        );

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

  /// Marks credits from senders the user has named as their salary payer.
  ///
  /// Runs on every scan rather than being written into stored data, so the
  /// answer follows the user's current choice: unmark a sender and the next
  /// scan stops treating it as salary, with nothing left behind to clean up.
  ///
  /// Only credits are eligible. Naming a sender cannot turn money leaving the
  /// account into income, however the message is worded.
  List<FinanceTxn> _applyUserSalarySenders(List<FinanceTxn> txns) {
    final senders = ref.read(spendCompletenessProvider).userSalarySenders;
    if (senders.isEmpty) return txns;
    return [
      for (final txn in txns)
        if (txn.direction == TxnDirection.credit &&
            !txn.isSalary &&
            senders.contains(normalizeSalarySource(txn.sender)))
          txn.copyWith(isSalary: true)
        else
          txn,
    ];
  }

  /// Stable identity for a parsed transaction. A list index cannot be used to
  /// recognise a transaction across scans — a scan rebuilds the whole list from
  /// the inbox — so we key on the payment reference, else the source SMS id,
  /// else the amount/direction/day/merchant signature.
  static String _txnIdentity(FinanceTxn txn) {
    final ref = txn.refNo;
    if (ref != null && ref.isNotEmpty) return 'ref:$ref';
    final smsId = txn.smsId;
    if (smsId != null) return 'sms:$smsId';
    return 'sig:${txn.amount}|${txn.direction.name}|'
        '${txn.date.year}-${txn.date.month}-${txn.date.day}|'
        '${MerchantCategoryRules.keyFor(txn.merchant) ?? ''}';
  }

  /// Re-applies everything already known about a payee to a freshly parsed scan,
  /// so a re-scan neither loses work nor pays for it twice.
  ///
  /// A scan rebuilds every transaction from the inbox, and switching the period
  /// chip (1 / 3 / 6 / 12 months, for the trend charts) triggers exactly that.
  /// Four sources are re-applied, strongest first:
  ///
  ///   1. the user's correction of this exact transaction
  ///   2. the user's rule for this payee
  ///   3. the AI answer for this exact transaction
  ///   4. the AI answer for this payee, from any earlier scan
  ///
  /// 3 and 4 are what keep the shared budget intact: once a payee has been
  /// classified it is never sent again, so widening the window from one month to
  /// twelve only ever pays for payees genuinely seen for the first time.
  List<FinanceTxn> _applyKnownCategories(
    List<FinanceTxn> txns,
    SpendMap? previous,
  ) {
    final knownByIdentity =
        <String, ({String category, CategorySource source})>{};
    for (final txn in previous?.txns ?? const <FinanceTxn>[]) {
      if (txn.categorySource == CategorySource.manual ||
          txn.categorySource == CategorySource.ai) {
        knownByIdentity[_txnIdentity(txn)] = (
          category: txn.category,
          source: txn.categorySource,
        );
      }
    }
    if (knownByIdentity.isEmpty &&
        _categoryRules.isEmpty &&
        _aiMemory.isEmpty) {
      return txns;
    }
    return [for (final txn in txns) _withKnownCategory(txn, knownByIdentity)];
  }

  FinanceTxn _withKnownCategory(
    FinanceTxn txn,
    Map<String, ({String category, CategorySource source})> knownByIdentity,
  ) {
    if (txn.direction != TxnDirection.debit) return txn;

    final manualRule = _categoryRules.categoryFor(txn.merchant);
    final known = knownByIdentity[_txnIdentity(txn)];
    // A manual rule outranks a carried-over AI answer even for the same
    // transaction: the user corrected the payee, so that verdict stands.
    final (String? chosen, CategorySource source) = switch (known) {
      final k? when k.source == CategorySource.manual => (
          k.category,
          CategorySource.manual,
        ),
      _ when manualRule != null => (manualRule, CategorySource.manual),
      final k? => (k.category, CategorySource.ai),
      _ => (_aiMemory.categoryFor(txn.merchant), CategorySource.ai),
    };

    // A stale or hand-edited blob must not be able to inject a category the app
    // does not understand.
    if (chosen == null || !SpendCategory.assignable.contains(chosen)) {
      return txn;
    }
    return txn.copyWith(category: chosen, categorySource: source);
  }

  /// Stores the payees this AI pass resolved, so no later scan pays to classify
  /// them again. Written once per pass rather than per payee.
  Future<void> _rememberAiCategories(Map<String, String> resolved) async {
    var memory = _aiMemory;
    for (final entry in resolved.entries) {
      if (MerchantCategoryRules.keyFor(entry.key) == null) continue;
      if (memory.categoryFor(entry.key) == entry.value) continue;
      memory = memory.withRule(entry.key, entry.value);
    }
    // withRule returns a new instance only when it actually stored something,
    // so identity is enough to detect "nothing new to write".
    if (identical(memory, _aiMemory)) return;
    _aiMemory = memory;
    await _storage.write(
      UserScopedStorageKeys.spendCategoryAiMemory(_uid()),
      _aiMemory.toJsonString(),
    );
  }

  /// Records "this merchant means this category" so later scans file it without
  /// asking again. Silently ignored when the transaction has no merchant name
  /// long enough to key a rule on.
  Future<void> _rememberMerchantCategory(
    String? merchant,
    String category,
  ) async {
    if (MerchantCategoryRules.keyFor(merchant) == null) return;
    if (_categoryRules.categoryFor(merchant) == category) return;
    _categoryRules = _categoryRules.withRule(merchant, category);
    await _storage.write(
      UserScopedStorageKeys.spendCategoryRules(_uid()),
      _categoryRules.toJsonString(),
    );
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
    // Validated against `assignable`, not `all`: `all` is the flat picker list
    // and omits the insurance sub-types, so choosing "Car insurance" used to be
    // rejected here and silently did nothing.
    if (current == null ||
        transactionIndex < 0 ||
        transactionIndex >= current.txns.length ||
        !_isAssignableCategory(category)) {
      return;
    }
    final txns = [...current.txns];
    final corrected = txns[transactionIndex].copyWith(
      category: category,
      categorySource: CategorySource.manual,
    );
    txns[transactionIndex] = corrected;
    await _rememberMerchantCategory(corrected.merchant, category);
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

  /// A manual correction may use a built-in category or one the user created.
  /// Unknown custom ids are rejected so a stale id cannot be filed against a
  /// category that no longer exists in the picker.
  /// Whether [category] is something a transaction may actually hold: a built-in
  /// (including the insurance sub-types, which `all` omits because it is the flat
  /// picker list), or a custom category the user currently has. A stale custom id
  /// whose category has since been deleted is refused.
  bool _isAssignableCategory(String category) {
    if (SpendCategory.assignable.contains(category)) return true;
    if (!SpendCategory.isCustom(category)) return false;
    return ref.read(customSpendCategoriesProvider.notifier).contains(category);
  }

  // Runs of 5+ digits (account/card numbers, phone numbers) stripped before any
  // text leaves the device.
  static final RegExp _longDigitRun = RegExp(r'\d{5,}');
  // Masked account and card tails ("A/c XX1234", "card ending 4321"). These are
  // only three or four digits, so the rule above lets them through — and four
  // digits of a real account number is not something to hand a third party for
  // a category guess. The parsed endpoint stays on the device; nothing about
  // which account moved is ever needed to name a payee.
  static final RegExp _maskedTail = RegExp(
    r'(?:a\/c|ac|acct|account|card|ending|xx+)[\s:.#-]*(?:no\.?\s*)?'
    r'[x*]{0,6}\s*\d{3,6}\b',
    caseSensitive: false,
  );
  // Currency amounts (Rs/INR/₹ 1,234.56). Not needed to categorize, so dropped.
  static final RegExp _amountToken = RegExp(
    r'(?:rs\.?|inr|₹)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?',
    caseSensitive: false,
  );

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
        .replaceAll(_maskedTail, '')
        .replaceAll(_longDigitRun, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Coarse size band for a transaction. The exact figure is redacted before
  /// anything leaves the device; a band still lets the classifier use size as a
  /// weak tiebreaker (₹8,000 at "APOLLO" leans tyres over a pharmacy strip)
  /// without shipping the amount itself.
  static String _amountBand(int amount) {
    if (amount < 200) return '<₹200';
    if (amount < 500) return '₹200-500';
    if (amount < 1000) return '₹500-1k';
    if (amount < 5000) return '₹1k-5k';
    if (amount < 20000) return '₹5k-20k';
    return '₹20k+';
  }

  /// Max distinct payees per request. Matches the backend's cap.
  static const _aiBatchLimit = 60;

  /// Sends the still-`other` debit transactions to the AI fallback and merges
  /// back any confident category/merchant. Returns an updated, persisted map,
  /// or null when nothing changed (no candidates, signed out, AI unavailable).
  ///
  /// Requests are grouped by payee, not by transaction: a hundred Swiggy orders
  /// are one item to classify and one answer to apply. That is what keeps the
  /// shared budget viable, and it also means every transaction from one payee
  /// gets the same category instead of drifting apart between scans.
  Future<SpendMap?> _enrichCategoriesWithAi(SpendMap map) async {
    // Only debits the rules could not place, that the user has not already
    // corrected by hand.
    final candidates = <int>[];
    for (var i = 0; i < map.txns.length; i++) {
      final t = map.txns[i];
      // Internal movement is never sent: it needs no category, and paying for a
      // guess about the user's own transfer wastes a budget shared by everyone.
      if (t.direction == TxnDirection.debit &&
          !t.isInternalTransfer &&
          t.category == SpendCategory.other &&
          t.categorySource == CategorySource.rules) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return null;

    // Group by normalised merchant. Transactions with no readable payee cannot
    // be grouped and go one at a time, keyed by index.
    final groups = <String, List<int>>{};
    for (final i in candidates) {
      final key = MerchantCategoryRules.keyFor(map.txns[i].merchant);
      final id = key == null ? 't:$i' : 'm:$key';
      final group = groups.putIfAbsent(id, () => <int>[]);
      group.add(i);
      if (groups.length > _aiBatchLimit) {
        groups.remove(id);
        break;
      }
    }

    // Build minimal redacted items; drop any with nothing useful left to send.
    final items = <({
      String id,
      String text,
      String? merchant,
      String? sender,
      String? amountBand,
    })>[];
    for (final entry in groups.entries) {
      final txn = map.txns[entry.value.first];
      final text = _redactForAi(txn);
      if (text.isEmpty) continue;
      items.add((
        id: entry.key,
        text: text,
        merchant: txn.merchant,
        sender: txn.sender,
        amountBand: _amountBand(txn.amount),
      ));
    }
    if (items.isEmpty) return null;

    final guesses = await _sync.categorize(items);
    if (guesses.isEmpty) return null;

    final txns = [...map.txns];
    var changed = false;
    final resolved = <String, String>{};
    guesses.forEach((id, guess) {
      final indices = groups[id];
      if (indices == null) return;
      if (guess.confidence == 'low') return; // keep 'other' when unsure
      if (!SpendCategory.all.contains(guess.category)) return;
      for (final index in indices) {
        if (index < 0 || index >= txns.length) continue;
        final merchant = txns[index].merchant;
        txns[index] = txns[index].copyWith(
          category: guess.category,
          merchant: guess.merchant?.isNotEmpty == true ? guess.merchant : null,
          categorySource: CategorySource.ai,
        );
        // Remember against the merchant as PARSED, not as the model rewrote it
        // for display — the next scan looks up the parsed name.
        if (merchant != null) resolved[merchant] = guess.category;
        changed = true;
      }
    });
    if (!changed) return null;
    await _rememberAiCategories(resolved);

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

final spendMapProvider = NotifierProvider<SpendMapNotifier, SpendMapState>(
  SpendMapNotifier.new,
);
