import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage_service.dart';
import '../services/user_scoped_storage.dart';
import 'auth_provider.dart';

String _adjustmentsKey(String uid) =>
    UserScopedStorageKeys.spendMapAdjustments(uid);

/// User-edited monthly income (primary) and spend figures. Stored only on
/// device — never synced to the backend.
class SpendMapAdjustments {
  const SpendMapAdjustments({
    this.manualPrimaryMonthlyIncome,
    this.manualMonthlySpend,
    this.primaryIncomeUpdatedAt,
  });

  final int? manualPrimaryMonthlyIncome;
  final int? manualMonthlySpend;
  final DateTime? primaryIncomeUpdatedAt;

  bool get hasManualPrimaryIncome =>
      manualPrimaryMonthlyIncome != null && manualPrimaryMonthlyIncome! > 0;

  bool get hasManualMonthlySpend =>
      manualMonthlySpend != null && manualMonthlySpend! > 0;

  SpendMapAdjustments copyWith({
    int? Function()? manualPrimaryMonthlyIncome,
    int? Function()? manualMonthlySpend,
    DateTime? Function()? primaryIncomeUpdatedAt,
  }) {
    return SpendMapAdjustments(
      manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome != null
          ? manualPrimaryMonthlyIncome()
          : this.manualPrimaryMonthlyIncome,
      manualMonthlySpend: manualMonthlySpend != null
          ? manualMonthlySpend()
          : this.manualMonthlySpend,
      primaryIncomeUpdatedAt: primaryIncomeUpdatedAt != null
          ? primaryIncomeUpdatedAt()
          : this.primaryIncomeUpdatedAt,
    );
  }
}

class SpendMapAdjustmentsNotifier extends Notifier<SpendMapAdjustments> {
  final _storage = const SecureStorageService();
  int _mutationRevision = 0;

  @override
  SpendMapAdjustments build() {
    Future.microtask(_load);
    return const SpendMapAdjustments();
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  Future<void> _load() async {
    final revisionAtStart = _mutationRevision;
    final raw = await _storage.read(_adjustmentsKey(_uid()));
    if (raw == null || !ref.mounted || revisionAtStart != _mutationRevision) {
      return;
    }
    final parts = raw.split('|');
    if (parts.length < 2) return;
    state = SpendMapAdjustments(
      manualPrimaryMonthlyIncome: _parseOptional(parts[0]),
      manualMonthlySpend: _parseOptional(parts[1]),
      primaryIncomeUpdatedAt:
          parts.length >= 3 ? DateTime.tryParse(parts[2]) : null,
    );
  }

  int? _parseOptional(String value) {
    if (value.isEmpty) return null;
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  Future<void> _persist() async {
    final income = state.manualPrimaryMonthlyIncome?.toString() ?? '';
    final spend = state.manualMonthlySpend?.toString() ?? '';
    final incomeUpdatedAt =
        state.primaryIncomeUpdatedAt?.toIso8601String() ?? '';
    await _storage.write(
      _adjustmentsKey(_uid()),
      '$income|$spend|$incomeUpdatedAt',
    );
  }

  Future<void> setManualPrimaryIncome(int amount) async {
    if (amount <= 0) return;
    _mutationRevision++;
    state = state.copyWith(
      manualPrimaryMonthlyIncome: () => amount,
      primaryIncomeUpdatedAt: DateTime.now,
    );
    await _persist();
  }

  Future<void> clearManualPrimaryIncome() async {
    _mutationRevision++;
    state = state.copyWith(
      manualPrimaryMonthlyIncome: () => null,
      primaryIncomeUpdatedAt: () => null,
    );
    await _persist();
  }

  Future<void> setManualMonthlySpend(int amount) async {
    if (amount <= 0) return;
    _mutationRevision++;
    state = state.copyWith(manualMonthlySpend: () => amount);
    await _persist();
  }

  Future<void> clearManualMonthlySpend() async {
    _mutationRevision++;
    state = state.copyWith(manualMonthlySpend: () => null);
    await _persist();
  }

  Future<void> clearAll() async {
    _mutationRevision++;
    state = const SpendMapAdjustments();
    final uid = _uid();
    if (uid != 'guest') {
      await _storage.delete(_adjustmentsKey(uid));
    }
  }

  Future<void> clearLocalData() => clearAll();
}

final spendMapAdjustmentsProvider =
    NotifierProvider<SpendMapAdjustmentsNotifier, SpendMapAdjustments>(
  SpendMapAdjustmentsNotifier.new,
);
