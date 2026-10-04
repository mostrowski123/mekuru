import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

import 'shared/test_database.dart';

void main() {
  test('every entry downloads over https and has a distinct title', () {
    for (final entry in CatalogDictionary.values) {
      expect(entry.url, startsWith('https://'), reason: entry.displayName);
      expect(entry.indexUrl, startsWith('https://'), reason: entry.displayName);
      expect(
        entry.sourceUrl,
        startsWith('https://'),
        reason: entry.displayName,
      );
    }
    final titles = CatalogDictionary.values.map((e) => e.title).toList();
    expect(titles.toSet(), hasLength(titles.length));
  });

  test('titles match with or without a revision, and nothing else', () {
    const jmnedict = CatalogDictionary.jmnedict;
    expect(jmnedict.matchesTitle('JMnedict'), isTrue);
    expect(jmnedict.matchesTitle('JMnedict [2026-10-03]'), isTrue);
    expect(jmnedict.matchesTitle('JMnedict (old)'), isFalse);
    expect(jmnedict.matchesTitle('JMdict [2026-10-03]'), isFalse);
    expect(
      CatalogDictionary.forTitle('Jitendex.org [2026-10-03]'),
      CatalogDictionary.jitendex,
    );
    expect(
      CatalogDictionary.forTitle('wty-ja-ja'),
      CatalogDictionary.wiktionaryJapanese,
    );
    expect(CatalogDictionary.forTitle('JMdict [2026-10-03]'), isNull);
  });

  test('catalog editions are installed as themselves, never as the English '
      'JMdict or KANJIDIC', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    for (final entry in CatalogDictionary.values) {
      await repo.insertDictionary('${entry.title} [2026-10-03]');
    }
    final installed = await repo.getAllDictionaries();

    for (final entry in CatalogDictionary.values) {
      expect(entry.isInstalledIn(installed), isTrue, reason: entry.displayName);
    }
    for (final type in YomitanDictType.values) {
      expect(
        await YomitanDictDownloadService.isImported(type, repo),
        isFalse,
        reason: type.name,
      );
    }
  });
}
