import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `RestoreService.applySettings` is the static, database-free half of
/// `restoreSettings` so the boot-time full restore can write preferences
/// before any `AppDatabase` exists.
void main() {
  test('applySettings writes typed values for app and reader keys', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await RestoreService.applySettings(
      prefs,
      const BackupSettings(
        app: {
          'app.theme_mode': 'dark',
          'app.lookup_font_size': 18.0,
          'app.filter_roman_letters': true,
          'app.auto_crop_white_threshold': 240,
        },
        reader: {'reader.font_size': 22.0, 'reader.keep_screen_on': false},
      ),
    );

    expect(prefs.getString('app.theme_mode'), 'dark');
    expect(prefs.getDouble('app.lookup_font_size'), 18.0);
    expect(prefs.getBool('app.filter_roman_letters'), isTrue);
    expect(prefs.getInt('app.auto_crop_white_threshold'), 240);
    expect(prefs.getDouble('reader.font_size'), 22.0);
    expect(prefs.getBool('reader.keep_screen_on'), isFalse);
  });

  test('applySettings writes string lists and skips other types', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await RestoreService.applySettings(
      prefs,
      const BackupSettings(
        app: {
          'app.list': ['kept', 'as', 'list'],
          'app.weird': {'not': 'a pref'},
          'app.theme_mode': 'light',
        },
        reader: {},
      ),
    );

    expect(prefs.getStringList('app.list'), ['kept', 'as', 'list']);
    expect(prefs.containsKey('app.weird'), isFalse);
    expect(prefs.getString('app.theme_mode'), 'light');
  });
}
