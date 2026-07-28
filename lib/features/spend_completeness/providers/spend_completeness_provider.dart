import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../engine/spend_completeness_engine.dart';
import '../models/spend_completeness_models.dart';

class SpendCompletenessNotifier extends Notifier<SpendCompletenessState> {
  final _storage = const SecureStorageService();
  late String _uid;

  @override
  SpendCompletenessState build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const SpendCompletenessState();
  }

  Future<void> _load(String uid) async {
    final raw =
        await _storage.read(UserScopedStorageKeys.spendCompleteness(uid));
    if (raw == null || !ref.mounted || uid != _uid) return;
    try {
      state = SpendCompletenessState.fromJsonString(raw);
    } catch (_) {
      // Corrupt local data is ignored. The next edit replaces it.
    }
  }

  Future<void> _persist() => _storage.write(
        UserScopedStorageKeys.spendCompleteness(_uid),
        state.toJsonString(),
      );

  Future<void> setTrustedSalarySource(String? sourceId) async {
    state = SpendCompletenessState(
      trustedSalarySourceId:
          sourceId == null ? null : normalizeSalarySource(sourceId),
      missingSources: state.missingSources,
      confirmedRecurringIds: state.confirmedRecurringIds,
      dismissedRecurringIds: state.dismissedRecurringIds,
      household: state.household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> setMissingSource(
    MissingSpendSource source,
    bool isMissing,
  ) async {
    final updated = {...state.missingSources};
    isMissing ? updated.add(source) : updated.remove(source);
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: updated,
      confirmedRecurringIds: state.confirmedRecurringIds,
      dismissedRecurringIds: state.dismissedRecurringIds,
      household: state.household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> confirmRecurring(String id) async {
    final confirmed = {...state.confirmedRecurringIds, id};
    final dismissed = {...state.dismissedRecurringIds}..remove(id);
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: state.missingSources,
      confirmedRecurringIds: confirmed,
      dismissedRecurringIds: dismissed,
      household: state.household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> dismissRecurring(String id) async {
    final confirmed = {...state.confirmedRecurringIds}..remove(id);
    final dismissed = {...state.dismissedRecurringIds, id};
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: state.missingSources,
      confirmedRecurringIds: confirmed,
      dismissedRecurringIds: dismissed,
      household: state.household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> restoreDismissedRecurring() async {
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: state.missingSources,
      confirmedRecurringIds: state.confirmedRecurringIds,
      household: state.household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> setHousehold(HouseholdPlan household) async {
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: state.missingSources,
      confirmedRecurringIds: state.confirmedRecurringIds,
      dismissedRecurringIds: state.dismissedRecurringIds,
      household: household,
      categoryBudgets: state.categoryBudgets,
    );
    await _persist();
  }

  Future<void> setCategoryBudget(String category, int? amount) async {
    final budgets = {...state.categoryBudgets};
    if (amount == null || amount <= 0) {
      budgets.remove(category);
    } else {
      budgets[category] = amount;
    }
    state = SpendCompletenessState(
      trustedSalarySourceId: state.trustedSalarySourceId,
      missingSources: state.missingSources,
      confirmedRecurringIds: state.confirmedRecurringIds,
      dismissedRecurringIds: state.dismissedRecurringIds,
      household: state.household,
      categoryBudgets: budgets,
    );
    await _persist();
  }

  Future<void> clearLocalData() async {
    state = const SpendCompletenessState();
    if (_uid != 'guest') {
      await _storage.delete(UserScopedStorageKeys.spendCompleteness(_uid));
    }
  }
}

final spendCompletenessProvider =
    NotifierProvider<SpendCompletenessNotifier, SpendCompletenessState>(
  SpendCompletenessNotifier.new,
);
