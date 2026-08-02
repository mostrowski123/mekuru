import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ReaderSettings.brightness', () {
    test('defaults to null (follow system)', () {
      const settings = ReaderSettings();
      expect(settings.brightness, isNull);
    });

    test('copyWith preserves brightness when not specified', () {
      const settings = ReaderSettings(brightness: 0.3);
      final copy = settings.copyWith(fontSize: 24);
      expect(copy.brightness, 0.3);
    });

    test('copyWith clearBrightness resets to follow-system', () {
      const settings = ReaderSettings(brightness: 0.3);
      final copy = settings.copyWith(clearBrightness: true);
      expect(copy.brightness, isNull);
    });
  });

  group('SharedPreferencesReaderSettingsStorage — brightness', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves brightness and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(brightness: 0.3));

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.brightness, 0.3);
    });

    test('saving null brightness removes the key', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(brightness: 0.3));
      await storage.save(const ReaderSettings());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('reader.brightness'), isFalse);
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.brightness, isNull);
    });

    test(
      'load returns settings when only the brightness key is present',
      () async {
        SharedPreferences.setMockInitialValues({'reader.brightness': 0.3});
        final storage = SharedPreferencesReaderSettingsStorage();
        final loaded = await storage.load();
        expect(loaded, isNotNull);
        expect(loaded!.brightness, 0.3);
      },
    );

    test('follows system (null) when only legacy keys are present', () async {
      // Simulate a user upgrading from a version without the brightness key.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.fontSize, 24);
      expect(loaded.brightness, isNull);
    });
  });
}
