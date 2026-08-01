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
    final raw = await _storage.read(
      UserScopedStorageKeys.spendCompleteness(uid),
    );
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
    state = state.copyWith(
      trustedSalarySourceId:
          sourceId == null ? null : normalizeSalarySource(sourceId),
      clearTrustedSalarySource: sourceId == null,
    );
    await _persist();
  }

  /// Records that [sender] pays the user's salary, whether or not the parser
  /// worked that out on its own.
  ///
  /// The user is the authority here for the same reason they are on categories:
  /// a keyword list cannot know that "NEFT CR-ACME TECHNOLOGIES" is payday and
  /// they do.
  Future<void> markSenderAsSalary(String sender) async {
    final key = normalizeSalarySource(sender);
    if (key.isEmpty) return;
    state =
        state.copyWith(userSalarySenders: {...state.userSalarySenders, key});
    await _persist();
  }

  Future<void> unmarkSenderAsSalary(String sender) async {
    final key = normalizeSalarySource(sender);
    if (!state.userSalarySenders.contains(key)) return;
    state = state.copyWith(
      userSalarySenders: {...state.userSalarySenders}..remove(key),
      // A source the user no longer calls salary cannot stay the trusted one.
      clearTrustedSalarySource: state.trustedSalarySourceId == key,
    );
    await _persist();
  }

  Future<void> setMissingSource(
    MissingSpendSource source,
    bool isMissing,
  ) async {
    final updated = {...state.missingSources};
    isMissing ? updated.add(source) : updated.remove(source);
    state = state.copyWith(missingSources: updated);
    await _persist();
  }

  Future<void> confirmRecurring(String id) async {
    state = state.copyWith(
      confirmedRecurringIds: {...state.confirmedRecurringIds, id},
      dismissedRecurringIds: {...state.dismissedRecurringIds}..remove(id),
    );
    await _persist();
  }

  Future<void> dismissRecurring(String id) async {
    state = state.copyWith(
      confirmedRecurringIds: {...state.confirmedRecurringIds}..remove(id),
      dismissedRecurringIds: {...state.dismissedRecurringIds, id},
    );
    await _persist();
  }

  Future<void> restoreDismissedRecurring() async {
    state = state.copyWith(dismissedRecurringIds: const {});
    await _persist();
  }

  Future<void> setHousehold(HouseholdPlan household) async {
    state = state.copyWith(household: household);
    await _persist();
  }

  Future<void> setCategoryBudget(String category, int? amount) async {
    final budgets = {...state.categoryBudgets};
    if (amount == null || amount <= 0) {
      budgets.remove(category);
    } else {
      budgets[category] = amount;
    }
    state = state.copyWith(categoryBudgets: budgets);
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
