import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('furiganaModeFromString', () {
    test('parses each storageValue', () {
      expect(furiganaModeFromString('off'), FuriganaMode.off);
      expect(furiganaModeFromString('all'), FuriganaMode.all);
      expect(furiganaModeFromString('aboveLevel'), FuriganaMode.aboveLevel);
    });

    test('returns off for null or unrecognized values', () {
      expect(furiganaModeFromString(null), FuriganaMode.off);
      expect(furiganaModeFromString(''), FuriganaMode.off);
      expect(furiganaModeFromString('on'), FuriganaMode.off);
      expect(furiganaModeFromString('ABOVE_LEVEL'), FuriganaMode.off);
    });

    test('round-trips every enum value via storageValue', () {
      for (final mode in FuriganaMode.values) {
        expect(furiganaModeFromString(mode.storageValue), mode);
      }
    });
  });

  group('ReaderSettings.furiganaMode', () {
    test('defaults to off', () {
      const settings = ReaderSettings();
      expect(settings.furiganaMode, FuriganaMode.off);
    });

    test('copyWith preserves furiganaMode when not specified', () {
      const settings = ReaderSettings(furiganaMode: FuriganaMode.all);
      final copy = settings.copyWith(fontSize: 24);
      expect(copy.furiganaMode, FuriganaMode.all);
    });

    test('copyWith updates furiganaMode when specified', () {
      const settings = ReaderSettings(furiganaMode: FuriganaMode.off);
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

    test('returns null when no settings have been saved', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      expect(await storage.load(), isNull);
    });

    test('returns off (default) when only legacy keys are present', () async {
      // Simulate a user upgrading from a version that did not have the
      // furigana key. The settings file has some other reader keys but no
      // 'reader.furigana_mode'.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.fontSize, 24);
      expect(loaded.furiganaMode, FuriganaMode.off);
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
