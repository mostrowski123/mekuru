import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ReaderSettings.splitVerticalText', () {
    test('defaults to false', () {
      const settings = ReaderSettings();
      expect(settings.splitVerticalText, isFalse);
    });

    test('copyWith preserves splitVerticalText when not specified', () {
      const settings = ReaderSettings(splitVerticalText: true);
      final copy = settings.copyWith(fontSize: 24);
      expect(copy.splitVerticalText, isTrue);
    });

    test('copyWith updates splitVerticalText when specified', () {
      const settings = ReaderSettings();
      final copy = settings.copyWith(splitVerticalText: true);
      expect(copy.splitVerticalText, isTrue);
    });
  });

  group('SharedPreferencesReaderSettingsStorage — splitVerticalText', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves splitVerticalText and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(splitVerticalText: true));

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.splitVerticalText, isTrue);
    });

    test('defaults to false when only legacy keys are present', () async {
      // Simulate a user upgrading from a version that did not have the
      // split vertical text key.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.splitVerticalText, isFalse);
    });

    test(
      'load returns settings when only splitVerticalText key is present',
      () async {
        SharedPreferences.setMockInitialValues({
          'reader.split_vertical_text': true,
        });
        final storage = SharedPreferencesReaderSettingsStorage();
        final loaded = await storage.load();
        expect(loaded, isNotNull);
        expect(loaded!.splitVerticalText, isTrue);
      },
    );
  });
}
