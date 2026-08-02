import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('mangaViewModeFromString', () {
    test('parses each storageValue', () {
      expect(mangaViewModeFromString('singlePage'), MangaViewMode.singlePage);
      expect(
        mangaViewModeFromString('twoPageSpread'),
        MangaViewMode.twoPageSpread,
      );
      expect(mangaViewModeFromString('scroll'), MangaViewMode.scroll);
    });

    test('returns singlePage for null or unrecognized values', () {
      expect(mangaViewModeFromString(null), MangaViewMode.singlePage);
      expect(mangaViewModeFromString(''), MangaViewMode.singlePage);
      expect(mangaViewModeFromString('spread'), MangaViewMode.singlePage);
    });

    test('round-trips every enum value via storageValue', () {
      for (final mode in MangaViewMode.values) {
        expect(mangaViewModeFromString(mode.storageValue), mode);
      }
    });
  });

  group('SharedPreferencesReaderSettingsStorage — manga settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves all manga settings and reloads them', () async {
      final storage = SharedPreferencesReaderSettingsStorage();
      await storage.save(
        const ReaderSettings(
          mangaViewMode: MangaViewMode.twoPageSpread,
          mangaReadingDirection: ReaderDirection.ltr,
          mangaAutoCrop: true,
          mangaTransparentLookup: false,
        ),
      );

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.mangaViewMode, MangaViewMode.twoPageSpread);
      expect(loaded.mangaReadingDirection, ReaderDirection.ltr);
      expect(loaded.mangaAutoCrop, isTrue);
      expect(loaded.mangaTransparentLookup, isFalse);
    });

    test('upgrading from legacy prefs yields the old in-memory defaults', () async {
      // Before these settings were persisted they lived in bare in-memory
      // notifiers with these defaults; upgrading users must see no change.
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.mangaViewMode, MangaViewMode.singlePage);
      expect(loaded.mangaReadingDirection, ReaderDirection.rtl);
      expect(loaded.mangaAutoCrop, isFalse);
      expect(loaded.mangaTransparentLookup, isTrue);
    });
  });
}
