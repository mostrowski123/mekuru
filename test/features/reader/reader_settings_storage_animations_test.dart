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

  group('page turn style', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips every value and falls back to slide', () {
      for (final style in PageTurnStyle.values) {
        expect(pageTurnStyleFromString(style.storageValue), style);
      }
      expect(pageTurnStyleFromString(null), PageTurnStyle.slide);
      expect(pageTurnStyleFromString('flip'), PageTurnStyle.slide);
    });

    test('is saved, reloaded and backed up', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(pageTurnStyle: PageTurnStyle.none),
      );
      expect((await storage.load())!.pageTurnStyle, PageTurnStyle.none);
      expect(
        SharedPreferencesReaderSettingsStorage.allKeys,
        contains('reader.page_turn_style'),
      );
    });

    test('is slide on a device that saved a dropped style', () async {
      SharedPreferences.setMockInitialValues({
        'reader.page_turn_style': 'curl',
      });
      final loaded = await SharedPreferencesReaderSettingsStorage().load();
      expect(loaded!.pageTurnStyle, PageTurnStyle.slide);
    });

    test('is slide for installs that predate it', () async {
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final loaded = await SharedPreferencesReaderSettingsStorage().load();
      expect(loaded!.pageTurnStyle, PageTurnStyle.slide);
      expect(const ReaderSettings().pageTurnStyle, PageTurnStyle.slide);
    });

    test('is none in effect whenever animations are off', () {
      PageTurnStyle effective(
        PageTurnStyle style, {
        bool animations = true,
        bool reduceMotion = false,
      }) => effectivePageTurnStyle(
        ReaderSettings(pageTurnStyle: style, readerAnimations: animations),
        disableAnimations: reduceMotion,
      );

      expect(effective(PageTurnStyle.slide), PageTurnStyle.slide);
      expect(effective(PageTurnStyle.none), PageTurnStyle.none);
      expect(
        effective(PageTurnStyle.slide, animations: false),
        PageTurnStyle.none,
      );
      expect(
        effective(PageTurnStyle.slide, reduceMotion: true),
        PageTurnStyle.none,
      );
    });
  });

  group('SharedPreferencesReaderSettingsStorage - volume buttons', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves the choice and reloads it', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(volumeKeyPageTurn: VolumeKeyPageTurn.upNext),
      );

      final loaded = await storage.load();
      expect(loaded!.volumeKeyPageTurn, VolumeKeyPageTurn.upNext);
    });

    test(
      'volume down turns forward for installs that predate the key',
      () async {
        SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});

        final loaded = await SharedPreferencesReaderSettingsStorage().load();
        expect(loaded!.volumeKeyPageTurn, VolumeKeyPageTurn.downNext);
      },
    );
  });
}
