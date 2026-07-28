import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/other_income_source.dart';
import '../services/secure_storage_service.dart';
import '../services/user_scoped_storage.dart';
import 'auth_provider.dart';

String _sourcesKey(String uid) => UserScopedStorageKeys.otherIncome(uid);
String _askedKey(String uid) => UserScopedStorageKeys.otherIncomeAsked(uid);

/// Manual "other income" entries (freelance, rent, side business, etc.) that
/// the user adds after the one-time follow-up question. Stored ONLY in the
/// device's secure storage (Keychain/Keystore) — never synced to the backend
/// and never included in the spend-map payload that is pushed remotely. Only
/// the resulting aggregate contributes to on-screen income figures.
class OtherIncomeNotifier extends Notifier<List<OtherIncomeSource>> {
  final _storage = const SecureStorageService();

  // In-memory so scan() can check it synchronously without an I/O round trip
  // on every call; loaded once from storage at startup and flipped
  // immediately (not just persisted) by [markAsked].
  bool _asked = false;

  @override
  List<OtherIncomeSource> build() {
    Future.microtask(_load);
    return const [];
  }

  String _uid() => ref.read(authProvider)?.uid ?? 'guest';

  Future<void> _load() async {
    final uid = _uid();
    final raw = await _storage.read(_sourcesKey(uid));
    final sources = OtherIncomeSource.decodeList(raw);
    final askedRaw = await _storage.read(_askedKey(uid));
    if (!ref.mounted) return;
    _asked = askedRaw == 'true';
    state = sources;
  }

  Future<void> _persist() async {
    await _storage.write(
        _sourcesKey(_uid()), OtherIncomeSource.encodeList(state));
  }

  Future<void> add(String label, int monthlyAmount) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || monthlyAmount <= 0) return;
    state = [
      ...state,
      OtherIncomeSource(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: trimmed,
        monthlyAmount: monthlyAmount,
      ),
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  int get totalMonthly => state.fold(0, (sum, s) => sum + s.monthlyAmount);

  /// Whether the one-time "any other income?" question has already been asked
  /// (yes or no) for this user, so it never nags on every scan.
  bool get hasAsked => _asked;

  Future<void> markAsked() async {
    _asked = true;
    await _storage.write(_askedKey(_uid()), 'true');
  }

  Future<void> clearLocalData() async {
    final uid = _uid();
    if (uid == 'guest') {
      state = const [];
      _asked = false;
      return;
    }
    await _storage.delete(_sourcesKey(uid));
    await _storage.delete(_askedKey(uid));
    _asked = false;
    state = const [];
  }
}

final otherIncomeProvider =
    NotifierProvider<OtherIncomeNotifier, List<OtherIncomeSource>>(
  OtherIncomeNotifier.new,
);
