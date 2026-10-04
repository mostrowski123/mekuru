import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

import 'shared/test_database.dart';

void main() {
  test('every entry downloads over https and has a distinct title', () {
    for (final entry in CatalogDictionary.values) {
      expect(entry.url, startsWith('https://'), reason: entry.displayName);
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

  test('KANJIDIC editions keep the name start kanji parsing looks for', () {
    for (final entry in CatalogDictionary.values) {
      if (entry.title.startsWith('KANJIDIC')) {
        expect(entry.displayName, startsWith('KANJIDIC'));
      }
    }
  });

  test('display names use catalog names and drop revisions', () {
    const shown = {
      'Jitendex.org [2026-10-03]': 'Jitendex',
      'wty-ja-en': 'Wiktionary (English)',
      'JMdict (Spanish) [2026-10-03]': 'JMdict (Español)',
      'JMdict [2026-10-03]': 'JMdict',
      'KANJIDIC [2026-276]': 'KANJIDIC',
      'Old Dict [2024.01.02]': 'Old Dict',
      'JPDBv2㋕': 'JPDBv2㋕',
      'My notes [draft]': 'My notes [draft]',
    };
    shown.forEach(
      (stored, name) =>
          expect(dictionaryDisplayName(stored), name, reason: stored),
    );
  });

  test('the version a display name leaves out', () {
    DictionaryMeta meta(String name, {String? revision}) => DictionaryMeta(
      id: 1,
      name: name,
      isEnabled: true,
      dateImported: DateTime(2026, 10, 4),
      sortOrder: 0,
      isHidden: false,
      revision: revision,
    );

    expect(
      dictionaryVersion(meta('JMdict [2026-10-03]', revision: 'JMdict.2026')),
      '2026-10-03',
    );
    expect(
      dictionaryVersion(meta('wty-ja-en', revision: '2026.10.02')),
      '2026.10.02',
    );
    expect(dictionaryVersion(meta('My dictionary')), isNull);
  });
}
