import 'package:mekuru/core/services/secret_store.dart';

/// Secure storage for per-connection server credentials: a Komga/Kavita API
/// key, or `user:password` for Komga basic auth. Keyed by the
/// ServerConnections row id. Secrets never enter the database or backups.
class ServerSecretStorage {
  static SecretStore _store(int connectionId) =>
      SecretStore('sync.server_secret_$connectionId');

  Future<String?> load(int connectionId) => _store(connectionId).load();

  Future<void> save(int connectionId, String secret) =>
      _store(connectionId).save(secret);

  Future<void> clear(int connectionId) => _store(connectionId).clear();
}
