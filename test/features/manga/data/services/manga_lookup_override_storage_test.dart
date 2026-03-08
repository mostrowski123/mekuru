import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/manga_lookup_override_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MangaLookupOverrideStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MangaLookupOverrideStorage();
  });

  group('MangaLookupOverrideStorage', () {
    test('saves and loads overrides for the same book and word', () async {
      await storage.saveOverride(
        bookId: 42,
        surfaceForm: '食べた',
        dictionaryForm: '食べる',
        lookupTerm: '食う',
      );

      final restored = await storage.loadOverride(
        bookId: 42,
        surfaceForm: '食べた',
        dictionaryForm: '食べる',
      );

      expect(restored, '食う');
    });

    test('keeps overrides isolated by book', () async {
      await storage.saveOverride(
        bookId: 42,
        surfaceForm: '見る',
        dictionaryForm: '見る',
        lookupTerm: '観る',
      );

      final restored = await storage.loadOverride(
        bookId: 7,
        surfaceForm: '見る',
        dictionaryForm: '見る',
      );

      expect(restored, isNull);
    });

    test('removes overrides cleanly', () async {
      await storage.saveOverride(
        bookId: 42,
        surfaceForm: '分かった',
        dictionaryForm: '分かる',
        lookupTerm: '判る',
      );

      await storage.removeOverride(
        bookId: 42,
        surfaceForm: '分かった',
        dictionaryForm: '分かる',
      );

      final restored = await storage.loadOverride(
        bookId: 42,
        surfaceForm: '分かった',
        dictionaryForm: '分かる',
      );
      final prefs = await SharedPreferences.getInstance();

      expect(restored, isNull);
      expect(prefs.getString(MangaLookupOverrideStorage.prefsKey), isNull);
    });
  });
}
