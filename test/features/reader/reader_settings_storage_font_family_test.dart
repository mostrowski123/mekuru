import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesReaderSettingsStorage - font family', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves the font and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(fontFamily: ReaderFontFamily.gothic),
      );

      final loaded = await storage.load();
      expect(loaded!.fontFamily, ReaderFontFamily.gothic);
    });

    test(
      'defaults to the book fonts for installs that predate the key',
      () async {
        SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});

        final loaded = await SharedPreferencesReaderSettingsStorage().load();
        expect(loaded!.fontFamily, ReaderFontFamily.book);
      },
    );

    test('saves an added font and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(
          fontFamily: ReaderFontFamily.custom,
          customFontFile: '游明朝.ttf',
        ),
      );

      final loaded = await storage.load();
      expect(loaded!.fontFamily, ReaderFontFamily.custom);
      expect(loaded.customFontFile, '游明朝.ttf');
    });

    test('no added font leaves the key absent', () async {
      await SharedPreferencesReaderSettingsStorage().save(
        const ReaderSettings(),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('reader.custom_font'), isFalse);
    });

    test('the key is backed up with the other reader keys', () {
      expect(
        SharedPreferencesReaderSettingsStorage.allKeys,
        contains('reader.custom_font'),
      );
    });
  });
}
