import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_readiness.dart';
import '../services/secure_storage_service.dart';
import 'auth_provider.dart';

String _documentChecklistKey(String uid) => 'arth_document_checklist_$uid';

class DocumentChecklistNotifier extends Notifier<Map<String, bool>> {
  final SecureStorageService _storage;

  DocumentChecklistNotifier([SecureStorageService? storage])
      : _storage = storage ?? const SecureStorageService();

  @override
  Map<String, bool> build() {
    _load();
    return const {};
  }

  String? _currentUid() => ref.read(authProvider)?.uid;

  Future<void> _load() async {
    final uid = _currentUid();
    if (uid == null) return;

    final raw = await _storage.read(_documentChecklistKey(uid));
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final knownIds = taxDocumentItems.map((item) => item.id).toSet();
      if (!ref.mounted) return;
      state = {
        for (final entry in decoded.entries)
          if (knownIds.contains(entry.key)) entry.key: entry.value == true,
      };
    } catch (_) {}
  }

  Future<void> setReady(String id, bool ready) async {
    state = {...state, id: ready};
    await _persist();
  }

  Future<void> toggle(String id) => setReady(id, !(state[id] ?? false));

  Future<void> clear() async {
    state = const {};
    final uid = _currentUid();
    if (uid != null) {
      await _storage.delete(_documentChecklistKey(uid));
    }
  }

  Future<void> _persist() async {
    final uid = _currentUid();
    if (uid == null) return;
    await _storage.write(_documentChecklistKey(uid), jsonEncode(state));
  }
}

final documentChecklistProvider =
    NotifierProvider<DocumentChecklistNotifier, Map<String, bool>>(
  DocumentChecklistNotifier.new,
);

final documentReadinessPercentProvider = Provider<int>((ref) {
  return documentReadinessPercent(ref.watch(documentChecklistProvider));
});
