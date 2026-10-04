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
  });
}
