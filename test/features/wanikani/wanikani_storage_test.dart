import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/data/services/wanikani_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Stateless: everything lives in the mocked prefs/secure store reset per test.
const storage = WanikaniStorage();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final snapshot = WanikaniSnapshot(
    username: 'crabigator',
    level: 3,
    stages: {'日'.runes.first: 9},
    syncedAt: DateTime.utc(2026, 9, 10),
  );

  group('WanikaniStorage token', () {
    test('starts empty', () async {
      expect(await storage.loadToken(), isNull);
    });

    test('saves trimmed and reloads', () async {
      await storage.saveToken('  abc-123  ');
      expect(await storage.loadToken(), 'abc-123');
    });

    test('saving blank clears the token', () async {
      await storage.saveToken('abc');
      await storage.saveToken('   ');
      expect(await storage.loadToken(), isNull);
    });

    test('clearToken removes it', () async {
      await storage.saveToken('abc');
      await storage.clearToken();
      expect(await storage.loadToken(), isNull);
    });
  });

  group('WanikaniStorage snapshot', () {
    test('starts empty', () async {
      expect(await storage.loadSnapshot(), isNull);
    });

    test('round-trips under the backed-up key', () async {
      await storage.saveSnapshot(snapshot);
      final loaded = await storage.loadSnapshot();
      expect(loaded!.username, 'crabigator');
      expect(loaded.stages, snapshot.stages);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WanikaniStorage.snapshotPrefsKey), isNotNull);
      expect(BackupService.appKeys, contains(WanikaniStorage.snapshotPrefsKey));
    });

    test('corrupt value reads as never synced', () async {
      SharedPreferences.setMockInitialValues({
        WanikaniStorage.snapshotPrefsKey: '{oops',
      });
      expect(await storage.loadSnapshot(), isNull);
    });

    test('clearSnapshot removes the key', () async {
      await storage.saveSnapshot(snapshot);
      await storage.clearSnapshot();
      expect(await storage.loadSnapshot(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(WanikaniStorage.snapshotPrefsKey), isFalse);
    });

    test('the token never lands in SharedPreferences', () async {
      await storage.saveToken('secret-token');
      await storage.saveSnapshot(snapshot);
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(prefs.get(key).toString(), isNot(contains('secret-token')));
      }
    });
  });
}
