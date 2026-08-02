import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';

/// Guards against the backup key lists drifting out of sync with the storage
/// classes that own the preferences (which silently drops settings from
/// backups). The lists are derived today; these tests keep it that way.
void main() {
  group('backup key coverage', () {
    test('every reader storage key is backed up', () {
      expect(
        BackupService.readerKeys,
        containsAll(SharedPreferencesReaderSettingsStorage.allKeys),
      );
    });

    test('every app storage key is backed up', () {
      expect(
        BackupService.appKeys,
        containsAll(SharedPreferencesAppSettingsStorage.allKeys),
      );
    });

    test('keys use their expected namespace prefixes', () {
      for (final key in BackupService.readerKeys) {
        expect(key, startsWith('reader.'));
      }
      for (final key in BackupService.appKeys) {
        expect(key, anyOf(startsWith('app.'), startsWith('backup.')));
      }
    });

    test('key lists contain no duplicates', () {
      expect(
        BackupService.readerKeys.toSet().length,
        BackupService.readerKeys.length,
      );
      expect(BackupService.appKeys.toSet().length, BackupService.appKeys.length);
    });
  });
}
