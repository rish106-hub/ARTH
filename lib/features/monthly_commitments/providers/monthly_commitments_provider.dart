import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../models/monthly_commitment_models.dart';

class MonthlyCommitmentsNotifier extends Notifier<MonthlyCommitmentsState> {
  final _storage = const SecureStorageService();
  late String _uid;

  @override
  MonthlyCommitmentsState build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const MonthlyCommitmentsState();
  }

  Future<void> save(MonthlyCommitment commitment) async {
    final next = [
      commitment,
      ...state.manual.where((item) => item.id != commitment.id),
    ];
    state = state.withManual(next);
    await _persist();
  }

  Future<void> delete(String id) async {
    state =
        state.withManual(state.manual.where((item) => item.id != id).toList());
    await _persist();
  }

  Future<void> _load(String uid) async {
    final raw =
        await _storage.read(UserScopedStorageKeys.monthlyCommitments(uid));
    if (raw == null || !ref.mounted || uid != _uid) return;
    try {
      state = MonthlyCommitmentsState.fromJsonString(raw);
    } catch (_) {}
  }

  Future<void> _persist() => _storage.write(
        UserScopedStorageKeys.monthlyCommitments(_uid),
        state.toJsonString(),
      );
}

final monthlyCommitmentsProvider =
    NotifierProvider<MonthlyCommitmentsNotifier, MonthlyCommitmentsState>(
  MonthlyCommitmentsNotifier.new,
);
