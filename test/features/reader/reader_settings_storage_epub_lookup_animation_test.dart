import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesReaderSettingsStorage - EPUB lookup animation', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves the toggle and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(epubLookupAnimation: false));

      final loaded = await storage.load();
      expect(loaded!.epubLookupAnimation, isFalse);
    });

    test('defaults to animated for installs that predate the key', () async {
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});

      final loaded = await SharedPreferencesReaderSettingsStorage().load();
      expect(loaded!.epubLookupAnimation, isTrue);
    });
  });
}
