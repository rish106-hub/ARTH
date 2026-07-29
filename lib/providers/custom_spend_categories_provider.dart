import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/spend_map.dart';
import '../services/secure_storage_service.dart';
import '../services/user_scoped_storage.dart';
import 'auth_provider.dart';

String _categoriesKey(String uid) =>
    UserScopedStorageKeys.customSpendCategories(uid);

/// Spend categories the user added themselves, so a one-off payment they had to
/// name once — income tax, a premium, a fee — stays a clickable option for every
/// later transaction. Stored locally first and mirrored to the account's
/// encrypted durable-state backup, so the list follows the user to a new device.
class CustomSpendCategoriesNotifier
    extends Notifier<List<CustomSpendCategory>> {
  final _storage = const SecureStorageService();
  int _mutationRevision = 0;

  @override
  List<CustomSpendCategory> build() {
    Future.microtask(_load);
    return const [];
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  Future<void> _load() async {
    final revisionAtStart = _mutationRevision;
    final raw = await _storage.read(_categoriesKey(_uid()));
    if (raw == null || !ref.mounted || revisionAtStart != _mutationRevision) {
      return;
    }
    final restored = _decode(raw);
    if (restored.isEmpty) return;
    state = restored;
  }

  List<CustomSpendCategory> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final seen = <String>{};
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CustomSpendCategory.fromJson)
          .whereType<CustomSpendCategory>()
          .where((category) => seen.add(category.id))
          .take(CustomSpendCategory.maxPerUser)
          .toList(growable: false);
    } catch (_) {
      // A corrupt list must not block categorising. The next add rewrites it.
      return const [];
    }
  }

  Future<void> _persist() async {
    await _storage.write(
      _categoriesKey(_uid()),
      jsonEncode(state.map((category) => category.toJson()).toList()),
    );
  }

  /// Resolves [rawLabel] to a category id and makes it available for reuse.
  ///
  /// Returns the built-in id when the text names one, so typing "Rent" reuses
  /// the existing category rather than shadowing it. Returns null when the text
  /// holds no usable characters or the user is already at
  /// [CustomSpendCategory.maxPerUser].
  Future<String?> addFromUserText(String rawLabel) async {
    final id = SpendCategory.idForUserText(rawLabel);
    if (id == null || !SpendCategory.isCustom(id)) return id;

    final existing = state.where((category) => category.id == id).firstOrNull;
    if (existing != null) return existing.id;
    if (state.length >= CustomSpendCategory.maxPerUser) return null;

    _mutationRevision++;
    state = [
      ...state,
      CustomSpendCategory(id: id, label: rawLabel.trim()),
    ];
    await _persist();
    return id;
  }

  /// Forgets a category so it stops appearing in the picker. Transactions
  /// already filed under it keep their id and still render a readable name,
  /// because the id carries its own label.
  Future<void> remove(String id) async {
    if (!state.any((category) => category.id == id)) return;
    _mutationRevision++;
    state =
        state.where((category) => category.id != id).toList(growable: false);
    await _persist();
  }

  bool contains(String id) => state.any((category) => category.id == id);

  Future<void> clearLocalData() async {
    _mutationRevision++;
    state = const [];
    final uid = _uid();
    if (uid != 'guest') {
      await _storage.delete(_categoriesKey(uid));
    }
  }
}

final customSpendCategoriesProvider =
    NotifierProvider<CustomSpendCategoriesNotifier, List<CustomSpendCategory>>(
  CustomSpendCategoriesNotifier.new,
);

/// Built-in categories followed by the user's own, which is the order the
/// picker renders and the order that keeps familiar chips in stable positions.
final spendCategoryPickerProvider = Provider<List<String>>((ref) {
  final custom = ref.watch(customSpendCategoriesProvider);
  return [
    ...SpendCategory.all.where((category) => category != SpendCategory.other),
    ...custom.map((category) => category.id),
    SpendCategory.other,
  ];
});
