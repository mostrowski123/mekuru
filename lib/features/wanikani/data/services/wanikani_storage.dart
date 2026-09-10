import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wanikani_snapshot.dart';

/// Persistence for the WaniKani link. The API token lives only in secure
/// storage (never in the database or a backup); the sync snapshot is one
/// SharedPreferences JSON string that IS backed up, so a restored install
/// keeps hiding furigana until the user links again.
class WanikaniStorage {
  static const snapshotPrefsKey = 'app.wanikani_sync';
  static const _tokenKey = 'wanikani.api_token';

  final FlutterSecureStorage _secureStorage;

  const WanikaniStorage({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage;

  Future<String?> loadToken() async {
    final value = await _secureStorage.read(key: _tokenKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clearToken();
      return;
    }
    await _secureStorage.write(key: _tokenKey, value: trimmed);
  }

  Future<void> clearToken() => _secureStorage.delete(key: _tokenKey);

  Future<WanikaniSnapshot?> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return WanikaniSnapshot.decode(prefs.getString(snapshotPrefsKey));
  }

  Future<void> saveSnapshot(WanikaniSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(snapshotPrefsKey, snapshot.encode());
  }

  Future<void> clearSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(snapshotPrefsKey);
  }
}
