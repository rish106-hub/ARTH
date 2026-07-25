import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paycheck.dart';
import '../models/paycheck_override.dart';
import '../services/secure_storage_service.dart';
import 'auth_provider.dart';

String _overridesKey(String uid) => 'arth_paycheck_overrides_$uid';

/// User edits to the parsed paycheck breakdown — editing an amount, adding a
/// category the parser missed, or removing a line item entirely. Persisted
/// locally and re-applied on top of every fresh parse by PaycheckNotifier.
class PaycheckOverrideNotifier extends Notifier<List<PaycheckOverride>> {
  final _storage = const SecureStorageService();

  @override
  List<PaycheckOverride> build() {
    Future.microtask(_load);
    return const [];
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  Future<void> _load() async {
    final raw = await _storage.read(_overridesKey(_uid()));
    final overrides = PaycheckOverride.decodeList(raw);
    if (ref.mounted) state = overrides;
  }

  Future<void> _persist() async {
    await _storage.write(_overridesKey(_uid()), PaycheckOverride.encodeList(state));
  }

  /// Overrides the amount/label of an existing (parsed or previously-added)
  /// component.
  Future<void> editComponent(
    String canonicalKey,
    String label,
    int amount,
    PaycheckComponentKind kind,
  ) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || amount < 0) return;
    final wasManual = state
        .where((o) => o.canonicalKey == canonicalKey)
        .any((o) => o.isManualAdd);
    state = [
      ...state.where((o) => o.canonicalKey != canonicalKey),
      PaycheckOverride(
        canonicalKey: canonicalKey,
        label: trimmed,
        amount: amount,
        kind: kind,
        isManualAdd: wasManual,
      ),
    ];
    await _persist();
  }

  /// Adds a wholly new line item the parser never produced.
  Future<void> addComponent(
    String label,
    int amount,
    PaycheckComponentKind kind,
  ) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || amount <= 0) return;
    state = [
      ...state,
      PaycheckOverride(
        canonicalKey: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        label: trimmed,
        amount: amount,
        kind: kind,
        isManualAdd: true,
      ),
    ];
    await _persist();
  }

  /// Removes a component from the breakdown. A manually-added item is simply
  /// deleted from the override list; a parsed item is instead marked
  /// `removed` so it stays hidden the next time documents are re-parsed.
  Future<void> removeComponent(
    String canonicalKey,
    PaycheckComponentKind kind,
  ) async {
    final existing =
        state.where((o) => o.canonicalKey == canonicalKey).toList();
    if (existing.isNotEmpty && existing.first.isManualAdd) {
      state = state.where((o) => o.canonicalKey != canonicalKey).toList();
    } else {
      state = [
        ...state.where((o) => o.canonicalKey != canonicalKey),
        PaycheckOverride(
          canonicalKey: canonicalKey,
          label: '',
          amount: 0,
          kind: kind,
          removed: true,
        ),
      ];
    }
    await _persist();
  }
}

final paycheckOverrideProvider =
    NotifierProvider<PaycheckOverrideNotifier, List<PaycheckOverride>>(
  PaycheckOverrideNotifier.new,
);
