import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/money_goal.dart';
import '../services/money_goal_service.dart';

final moneyGoalServiceProvider = Provider<MoneyGoalService>(
  (ref) => MoneyGoalService(),
);

class MoneyGoalNotifier extends AsyncNotifier<List<MoneyGoal>> {
  late final MoneyGoalService _service;

  @override
  Future<List<MoneyGoal>> build() async {
    _service = ref.read(moneyGoalServiceProvider);
    try {
      return await _service.fetchGoals();
    } catch (_) {
      return const [];
    }
  }

  Future<MoneyGoal> save(MoneyGoal goal) async {
    final saved = await _service.saveGoal(goal);
    final previous = state.asData?.value ?? const <MoneyGoal>[];
    state = AsyncData([
      saved,
      ...previous.where((item) => item.id != saved.id),
    ]);
    return saved;
  }

  Future<void> delete(String id) async {
    await _service.deleteGoal(id);
    final previous = state.asData?.value ?? const <MoneyGoal>[];
    state = AsyncData(previous.where((goal) => goal.id != id).toList());
  }
}

final moneyGoalProvider =
    AsyncNotifierProvider<MoneyGoalNotifier, List<MoneyGoal>>(
  MoneyGoalNotifier.new,
);
