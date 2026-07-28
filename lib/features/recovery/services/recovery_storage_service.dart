import 'dart:convert';

import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../models/recovery_models.dart';

class RecoveryStorageService {
  const RecoveryStorageService({
    SecureStorageService storage = const SecureStorageService(),
  }) : _storage = storage;

  final SecureStorageService _storage;

  Future<RecoveryState> load(String uid) async {
    final raw = await _storage.read(UserScopedStorageKeys.recovery(uid));
    if (raw == null || raw.isEmpty) return const RecoveryState();
    try {
      return RecoveryState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const RecoveryState();
    }
  }

  Future<void> save(String uid, RecoveryState state) {
    return _storage.write(
      UserScopedStorageKeys.recovery(uid),
      jsonEncode(state.toJson()),
    );
  }
}
