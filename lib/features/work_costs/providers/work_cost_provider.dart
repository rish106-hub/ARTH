import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../models/work_cost_models.dart';

class WorkCostNotifier extends Notifier<WorkCostState> {
  final _storage = const SecureStorageService();
  late String _uid;

  @override
  WorkCostState build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const WorkCostState();
  }

  Future<void> setTag(
    String candidateId,
    WorkCostKind kind, {
    int? alternativeUnitCost,
  }) async {
    state = state.withTag(WorkCostTag(
      candidateId: candidateId,
      kind: kind,
      alternativeUnitCost: alternativeUnitCost,
    ));
    await _persist();
  }

  Future<void> removeTag(String candidateId) async {
    state = state.withoutTag(candidateId);
    await _persist();
  }

  Future<void> dismiss(String candidateId) async {
    state = state.dismiss(candidateId);
    await _persist();
  }

  Future<void> _load(String uid) async {
    final raw = await _storage.read(UserScopedStorageKeys.workCosts(uid));
    if (raw == null || !ref.mounted || uid != _uid) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = WorkCostState.fromJson(json);
    } catch (_) {
      // Invalid local state is ignored. The next user edit replaces it.
    }
  }

  Future<void> _persist() => _storage.write(
        UserScopedStorageKeys.workCosts(_uid),
        jsonEncode(state.toJson()),
      );
}

final workCostProvider = NotifierProvider<WorkCostNotifier, WorkCostState>(
  WorkCostNotifier.new,
);
