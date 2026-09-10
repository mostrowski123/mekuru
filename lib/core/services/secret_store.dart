import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One trimmed secret (API key, token, password) in platform secure storage.
/// Secrets never enter SharedPreferences, the database or backups; a blank
/// save clears the entry, and a stored blank reads as absent.
class SecretStore {
  final String key;
  final FlutterSecureStorage _storage;

  const SecretStore(
    this.key, {
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  Future<String?> load() async {
    final trimmed = (await _storage.read(key: key))?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> save(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? clear() : _storage.write(key: key, value: trimmed);
  }

  Future<void> clear() => _storage.delete(key: key);
}
