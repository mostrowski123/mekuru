import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('furiganaModeFromString', () {
    test('parses each storageValue', () {
      expect(furiganaModeFromString('hide'), FuriganaMode.hide);
      expect(furiganaModeFromString('book'), FuriganaMode.book);
      expect(furiganaModeFromString('all'), FuriganaMode.all);
      expect(furiganaModeFromString('aboveLevel'), FuriganaMode.aboveLevel);
    });

    test('reinterprets legacy "off" as book', () {
      // Versions <= 1.25.x persisted 'off' as a hide-everything default most
      // users never chose. Parsing it as `book` is the upgrade path — do not
      // "fix" this by adding an 'off' case to furiganaModeFromString.
      expect(furiganaModeFromString('off'), FuriganaMode.book);
    });

    test('returns book for null or unrecognized values', () {
      expect(furiganaModeFromString(null), FuriganaMode.book);
      expect(furiganaModeFromString(''), FuriganaMode.book);
      expect(furiganaModeFromString('on'), FuriganaMode.book);
      expect(furiganaModeFromString('ABOVE_LEVEL'), FuriganaMode.book);
    });

    test('round-trips every enum value via storageValue', () {
      for (final mode in FuriganaMode.values) {
        expect(furiganaModeFromString(mode.storageValue), mode);
      }
    });
  });

  group('ReaderSettings.furiganaMode', () {
    test('defaults to book', () {
      const settings = ReaderSettings();
      expect(settings.furiganaMode, FuriganaMode.book);
    });

    test('copyWith preserves furiganaMode when not specified', () {
      const settings = ReaderSettings(furiganaMode: FuriganaMode.all);
      final copy = settings.copyWith(fontSize: 24);
      expect(copy.furiganaMode, FuriganaMode.all);
    });

    test('copyWith updates furiganaMode when specified', () {
      const settings = ReaderSettings(furiganaMode: FuriganaMode.hide);
      final copy = settings.copyWith(furiganaMode: FuriganaMode.all);
      expect(copy.furiganaMode, FuriganaMode.all);
    });
  });

  group('SharedPreferencesReaderSettingsStorage — furiganaMode', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves furiganaMode and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(const ReaderSettings(furiganaMode: FuriganaMode.all));

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.furiganaMode, FuriganaMode.all);
    });

    test('round-trips aboveLevel', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(furiganaMode: FuriganaMode.aboveLevel),
      );

      final loaded = await storage.load();
      expect(loaded!.furiganaMode, FuriganaMode.aboveLevel);
    });

    test('persists hide and book as their literal storage strings', () async {
      final storage = SharedPreferencesReaderSettingsStorage();

      await storage.save(const ReaderSettings(furiganaMode: FuriganaMode.hide));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reader.furigana_mode'), 'hide');

      await storage.save(const ReaderSettings(furiganaMode: FuriganaMode.book));
      expect(prefs.getString('reader.furigana_mode'), 'book');
    });

    test('returns null when no settings have been saved', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      expect(await storage.load(), isNull);
    });

    test('returns book (default) when only legacy keys are present', () async {
      // Simulate a user upgrading from a version that did not have the
      // furigana key. The settings file has some other reader keys but no
      // 'reader.furigana_mode'.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.fontSize, 24);
      expect(loaded.furiganaMode, FuriganaMode.book);
    });

    test('a stored legacy "off" preference loads as book', () async {
      // The global half of the retroactive 'off' -> book conversion.
      SharedPreferences.setMockInitialValues({'reader.furigana_mode': 'off'});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded!.furiganaMode, FuriganaMode.book);
    });

    test(
      'load returns settings when only furiganaMode key is present',
      () async {
        SharedPreferences.setMockInitialValues({'reader.furigana_mode': 'all'});
        final storage = SharedPreferencesReaderSettingsStorage();
        final loaded = await storage.load();
        expect(loaded, isNotNull);
        expect(loaded!.furiganaMode, FuriganaMode.all);
      },
    );
  });
}
