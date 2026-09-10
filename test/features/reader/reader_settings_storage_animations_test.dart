import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesReaderSettingsStorage - reader animations', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves the toggle and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(readerAnimations: false));

      final loaded = await storage.load();
      expect(loaded!.readerAnimations, isFalse);
    });

    test('keeps honouring the key the manga-only toggle wrote', () async {
      SharedPreferences.setMockInitialValues({
        'reader.manga_page_turn_animation': false,
      });

      final loaded = await SharedPreferencesReaderSettingsStorage().load();
      expect(loaded!.readerAnimations, isFalse);
    });

    test('defaults to animated for installs that predate the key', () async {
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});

      final loaded = await SharedPreferencesReaderSettingsStorage().load();
      expect(loaded!.readerAnimations, isTrue);
    });
  });
}
