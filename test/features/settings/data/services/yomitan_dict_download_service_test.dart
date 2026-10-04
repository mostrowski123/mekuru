import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

import '../../../../shared/test_database.dart';

void main() {
  group('YomitanDictDownloadService.assetUrl', () {
    test('points at releases/latest/download so no GitHub API call is needed', () {
      // The api.github.com "latest release" endpoint is rate-limited to 60
      // unauthenticated requests per hour per IP, which real users hit (CGNAT
      // IPs shared by many devices). The latest/download form is served by
      // github.com directly and is not subject to the API rate limit.
      expect(
        YomitanDictDownloadService.assetUrl(YomitanDictType.jmdictEnglish),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english.zip',
      );
      expect(
        YomitanDictDownloadService.assetUrl(
          YomitanDictType.jmdictEnglishWithExamples,
        ),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english_with_examples.zip',
      );
      expect(
        YomitanDictDownloadService.assetUrl(YomitanDictType.kanjidicEnglish),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/KANJIDIC_english.zip',
      );
    });
  });

  group('YomitanDictDownloadService installed detection', () {
    late AppDatabase db;
    late DictionaryRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = DictionaryRepository(db);
    });

    tearDown(() => db.close());

    Future<bool> imported(YomitanDictType type) =>
        YomitanDictDownloadService.isImported(type, repo);

    test('another language edition is not the English one', () async {
      await repo.insertDictionary('JMdict (Spanish) [2026-10-03]');
      await repo.insertDictionary('KANJIDIC (French) [2026-276]');

      expect(await imported(YomitanDictType.jmdictEnglish), isFalse);
      expect(await imported(YomitanDictType.kanjidicEnglish), isFalse);
    });

    test('English titles, old and new, still count', () async {
      const cases = {
        'JMdict [2026-10-03]': YomitanDictType.jmdictEnglish,
        'JMdict (English)': YomitanDictType.jmdictEnglish,
        'KANJIDIC [2026-276]': YomitanDictType.kanjidicEnglish,
        'KANJIDIC (English)': YomitanDictType.kanjidicEnglish,
      };
      for (final MapEntry(key: title, value: type) in cases.entries) {
        final id = await repo.insertDictionary(title);
        expect(await imported(type), isTrue, reason: title);
        await repo.deleteDictionary(id);
      }
    });

    test('delete removes the English edition, not another language', () async {
      // Inserted first, so it sorts ahead of the English edition.
      await repo.insertDictionary('JMdict (Spanish) [2026-10-03]');
      await repo.insertDictionary('JMdict [2026-10-03]');

      await YomitanDictDownloadService.delete(
        YomitanDictType.jmdictEnglish,
        repo,
      );

      final names = (await repo.getAllDictionaries()).map((d) => d.name);
      expect(names, ['JMdict (Spanish) [2026-10-03]']);
    });
  });
}
