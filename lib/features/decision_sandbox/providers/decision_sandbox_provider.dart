import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../models/decision_sandbox_models.dart';

class DecisionSandboxNotifier extends Notifier<DecisionSandboxState> {
  final _storage = const SecureStorageService();
  late String _uid;

  @override
  DecisionSandboxState build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const DecisionSandboxState();
  }

  Future<void> save(DecisionScenario scenario) async {
    state = DecisionSandboxState(
      scenarios: [
        scenario,
        ...state.scenarios.where((item) => item.id != scenario.id),
      ],
    );
    await _persist();
  }

  Future<void> delete(String id) async {
    state = DecisionSandboxState(
      scenarios: state.scenarios.where((item) => item.id != id).toList(),
    );
    await _persist();
  }

  Future<void> duplicate(DecisionScenario scenario) async {
    await save(DecisionScenario(
      id: 'scenario_${DateTime.now().microsecondsSinceEpoch}',
      name: '${scenario.name} copy',
      kind: scenario.kind,
      monthlyIncomeChange: scenario.monthlyIncomeChange,
      currentMonthlyCost: scenario.currentMonthlyCost,
      proposedMonthlyCost: scenario.proposedMonthlyCost,
      oneOffCost: scenario.oneOffCost,
      createdAt: DateTime.now(),
      goalId: scenario.goalId,
    ));
  }

  Future<void> _load(String uid) async {
    final raw = await _storage.read(UserScopedStorageKeys.decisionSandbox(uid));
    if (raw == null || !ref.mounted || uid != _uid) return;
    try {
      state = DecisionSandboxState.fromJsonString(raw);
    } catch (_) {}
  }

  Future<void> _persist() => _storage.write(
        UserScopedStorageKeys.decisionSandbox(_uid),
        state.toJsonString(),
      );
}

final decisionSandboxProvider =
    NotifierProvider<DecisionSandboxNotifier, DecisionSandboxState>(
  DecisionSandboxNotifier.new,
);
