import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ReaderSettings.scrollView', () {
    test('defaults to false', () {
      const settings = ReaderSettings();
      expect(settings.scrollView, isFalse);
    });

    test('copyWith preserves scrollView when not specified', () {
      const settings = ReaderSettings(scrollView: true);
      final copy = settings.copyWith(fontSize: 24);
      expect(copy.scrollView, isTrue);
    });

    test('copyWith updates scrollView when specified', () {
      const settings = ReaderSettings();
      final copy = settings.copyWith(scrollView: true);
      expect(copy.scrollView, isTrue);
    });
  });

  group('SharedPreferencesReaderSettingsStorage — scrollView', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves scrollView and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(scrollView: true));

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.scrollView, isTrue);
    });

    test('defaults to false when only legacy keys are present', () async {
      // Simulate a user upgrading from a version that did not have the
      // scroll view key.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.scrollView, isFalse);
    });

    test('load returns settings when only scrollView key is present', () async {
      SharedPreferences.setMockInitialValues({'reader.scroll_view': true});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.scrollView, isTrue);
    });
  });
}
