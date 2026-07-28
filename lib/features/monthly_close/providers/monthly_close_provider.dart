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

class MonthlyCloseNotifier extends Notifier<MonthlyCloseRecord> {
  final _storage = const SecureStorageService();
  late String _uid;
  int _mutationRevision = 0;

  @override
  MonthlyCloseRecord build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    final record = _emptyRecord();
    Future.microtask(() => _load(_uid));
    return record;
  }

  MonthlyCloseRecord _emptyRecord() => MonthlyCloseRecord(
        periodKey: MonthlyCloseEngine.periodKey(DateTime.now()),
      );

  Future<void> _load(String uid) async {
    final revision = _mutationRevision;
    final raw = await _storage.read(UserScopedStorageKeys.monthlyClose(uid));
    if (raw == null ||
        !ref.mounted ||
        uid != _uid ||
        revision != _mutationRevision) {
      return;
    }
    try {
      final loaded = MonthlyCloseRecord.fromJsonString(raw);
      state = loaded.periodKey == MonthlyCloseEngine.periodKey(DateTime.now())
          ? loaded
          : _emptyRecord();
    } catch (_) {
      // Corrupt local state is ignored. The next check writes a clean record.
    }
  }

  Future<void> setStep(MonthlyCloseStep step, bool complete) async {
    _mutationRevision++;
    state = state.mark(step, complete, DateTime.now());
    await _storage.write(
      UserScopedStorageKeys.monthlyClose(_uid),
      state.toJsonString(),
    );
  }

  Future<void> clearLocalData() async {
    _mutationRevision++;
    state = _emptyRecord();
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
  final documents = ref.watch(taxDocumentProvider).asData?.value ?? const [];
  return MonthlyCloseEngine.build(
    paycheck: ref.watch(paycheckProvider),
    income: ref.watch(incomeSignalProvider),
    adjustments: ref.watch(spendMapAdjustmentsProvider),
    documents: documents,
    profile: ref.watch(userProfileProvider),
    now: DateTime.now(),
  );
});
