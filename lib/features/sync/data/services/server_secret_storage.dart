import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for per-connection server credentials: a Komga/Kavita API
/// key, or `user:password` for Komga basic auth. Keyed by the
/// ServerConnections row id. Secrets never enter the database or backups.
class ServerSecretStorage {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static String _key(int connectionId) => 'sync.server_secret_$connectionId';

  Future<String?> load(int connectionId) async {
    final value = await _secureStorage.read(key: _key(connectionId));
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> save(int connectionId, String secret) async {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) return clear(connectionId);
    await _secureStorage.write(key: _key(connectionId), value: trimmed);
  }

  Future<void> clear(int connectionId) =>
      _secureStorage.delete(key: _key(connectionId));
}
