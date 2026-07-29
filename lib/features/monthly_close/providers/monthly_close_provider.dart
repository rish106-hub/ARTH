import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/money_signals/providers/money_signal_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/paycheck_provider.dart';
import '../../../providers/spend_map_adjustments_provider.dart';
import '../../../providers/tax_document_provider.dart';
import '../../../providers/user_profile_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../engine/monthly_close_engine.dart';
import '../models/monthly_close_models.dart';

typedef MonthlyCloseClock = DateTime Function();

final monthlyCloseClockProvider = Provider<MonthlyCloseClock>(
  (ref) => () => DateTime.now(),
);

/// Aligns persisted close state with [now]. Prior months always start fresh.
MonthlyCloseRecord reconcileMonthlyCloseRecord({
  required MonthlyCloseRecord? stored,
  required DateTime now,
}) {
  final currentKey = MonthlyCloseEngine.periodKey(now);
  if (stored == null || stored.periodKey != currentKey) {
    return MonthlyCloseRecord(periodKey: currentKey);
  }
  return stored;
}

Duration delayUntilNextMonthBoundary(DateTime now) {
  final nextBoundary = DateTime(now.year, now.month + 1);
  return nextBoundary.difference(now);
}

class MonthlyCloseNotifier extends Notifier<MonthlyCloseRecord> {
  final _storage = const SecureStorageService();
  late String _uid;
  int _mutationRevision = 0;
  Timer? _periodTimer;

  DateTime _now() => ref.read(monthlyCloseClockProvider)();

  @override
  MonthlyCloseRecord build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    ref.onDispose(_disposePeriodTimer);
    final record = _emptyRecord();
    Future.microtask(() => _load(_uid));
    _schedulePeriodRollover();
    return record;
  }

  void _disposePeriodTimer() {
    _periodTimer?.cancel();
    _periodTimer = null;
  }

  void _schedulePeriodRollover() {
    _disposePeriodTimer();
    final delay = delayUntilNextMonthBoundary(_now());
    if (delay <= Duration.zero) return;
    _periodTimer = Timer(delay, _onPeriodBoundary);
  }

  void _onPeriodBoundary() {
    if (!ref.mounted) return;
    if (state.periodKey != MonthlyCloseEngine.periodKey(_now())) {
      unawaited(_resetForCurrentPeriod(persist: true));
    }
    _schedulePeriodRollover();
  }

  MonthlyCloseRecord _emptyRecord() => MonthlyCloseRecord(
        periodKey: MonthlyCloseEngine.periodKey(_now()),
      );

  Future<void> _load(String uid) async {
    final revision = _mutationRevision;
    final raw = await _storage.read(UserScopedStorageKeys.monthlyClose(uid));
    if (!ref.mounted || uid != _uid || revision != _mutationRevision) {
      return;
    }
    MonthlyCloseRecord? loaded;
    if (raw != null) {
      try {
        loaded = MonthlyCloseRecord.fromJsonString(raw);
      } catch (_) {
        loaded = null;
      }
    }
    final resolved = reconcileMonthlyCloseRecord(stored: loaded, now: _now());
    state = resolved;
    if (loaded != null && loaded.periodKey != resolved.periodKey) {
      await _persist(resolved);
    }
  }

  Future<void> _resetForCurrentPeriod({required bool persist}) async {
    _mutationRevision++;
    state = _emptyRecord();
    if (persist && _uid != 'guest') {
      await _persist(state);
    }
  }

  Future<void> _persist(MonthlyCloseRecord record) async {
    await _storage.write(
      UserScopedStorageKeys.monthlyClose(_uid),
      record.toJsonString(),
    );
  }

  Future<void> setStep(MonthlyCloseStep step, bool complete) async {
    final currentKey = MonthlyCloseEngine.periodKey(_now());
    if (state.periodKey != currentKey) {
      await _resetForCurrentPeriod(persist: false);
    }
    _mutationRevision++;
    state = state.mark(step, complete, _now());
    await _persist(state);
  }

  Future<void> clearLocalData() async {
    await _resetForCurrentPeriod(persist: false);
    if (_uid != 'guest') {
      await _storage.delete(UserScopedStorageKeys.monthlyClose(_uid));
    }
  }
}

final monthlyCloseProvider =
    NotifierProvider<MonthlyCloseNotifier, MonthlyCloseRecord>(
  MonthlyCloseNotifier.new,
);

final monthlyCloseSnapshotProvider = Provider<MonthlyCloseSnapshot>((ref) {
  ref.watch(monthlyCloseClockProvider);
  final documents = ref.watch(taxDocumentProvider).asData?.value ?? const [];
  return MonthlyCloseEngine.build(
    paycheck: ref.watch(paycheckProvider),
    income: ref.watch(incomeSignalProvider),
    adjustments: ref.watch(spendMapAdjustmentsProvider),
    documents: documents,
    profile: ref.watch(userProfileProvider),
    now: ref.read(monthlyCloseClockProvider)(),
  );
});
