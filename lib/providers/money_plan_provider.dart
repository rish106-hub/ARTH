import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/money_plan.dart';
import '../services/secure_storage_service.dart';
import 'auth_provider.dart';

String _moneyPlanKey(String uid) => 'arth_money_plan_$uid';

class MoneyPlanNotifier extends AsyncNotifier<MoneyPlan> {
  final SecureStorageService _storage;

  MoneyPlanNotifier([SecureStorageService? storage])
      : _storage = storage ?? const SecureStorageService();

  String get _uid => ref.read(authProvider)?.uid ?? 'local';

  @override
  Future<MoneyPlan> build() async {
    final raw = await _storage.read(_moneyPlanKey(_uid));
    if (raw == null || raw.isEmpty) return const MoneyPlan();
    try {
      return MoneyPlan.fromJsonString(raw);
    } catch (_) {
      await _storage.delete(_moneyPlanKey(_uid));
      return const MoneyPlan();
    }
  }

  Future<void> save(MoneyPlan plan) async {
    state = AsyncData(plan);
    await _storage.write(_moneyPlanKey(_uid), plan.toJsonString());
  }

  Future<void> clear() async {
    await _storage.delete(_moneyPlanKey(_uid));
    state = const AsyncData(MoneyPlan());
  }
}

final moneyPlanProvider = AsyncNotifierProvider<MoneyPlanNotifier, MoneyPlan>(
  MoneyPlanNotifier.new,
);
