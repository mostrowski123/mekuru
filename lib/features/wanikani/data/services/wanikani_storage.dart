import 'package:mekuru/core/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wanikani_snapshot.dart';

/// Persistence for the WaniKani link. The API token lives only in secure
/// storage (never in the database or a backup); the sync snapshot is one
/// SharedPreferences JSON string that IS backed up, so a restored install
/// keeps hiding furigana until the user links again.
class WanikaniStorage {
  static const snapshotPrefsKey = 'app.wanikani_sync';
  static const _token = SecretStore('wanikani.api_token');

  const WanikaniStorage();

  Future<String?> loadToken() => _token.load();

  Future<void> saveToken(String token) => _token.save(token);

  Future<void> clearToken() => _token.clear();

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
