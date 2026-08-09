import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

import 'shared/test_database.dart';

/// Katakana loanwords must be findable from every input family the search
/// screen accepts, like on jisho.org: romaji ("kaado", "ka-do"), hiragana
/// (かーど, かあど), and katakana (カード). Yomitan dictionaries store
/// loanwords with katakana expression AND reading, so hiragana/romaji input
/// needs katakana variant terms to reach them.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  late AppDatabase db;
  late DictionaryRepository repo;
  late DictionaryQueryService queryService;

  setUp(() async {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);

    final dictId = await repo.insertDictionary('Dict');
    await repo.batchInsertEntries([
      for (final (expression, gloss) in [
        ('カード', 'card'),
        ('コーヒー', 'coffee'),
        ('カメラ', 'camera'),
        ('パーティー', 'party'),
      ])
        DictionaryEntriesCompanion.insert(
          expression: expression,
          reading: Value(expression),
          glossaries: jsonEncode([gloss]),
          dictionaryId: dictId,
        ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<String>> search(String term) async {
    final results = await queryService.fuzzySearchWithSource(term);
    return results.map((r) => r.entry.expression).toSet();
  }

  group('katakana loanword lookup', () {
    test('finds カード from romaji with doubled vowel (kaado)', () async {
      expect(await search('kaado'), contains('カード'));
    });

    test('finds カード from romaji with hyphen (ka-do)', () async {
      expect(await search('ka-do'), contains('カード'));
    });

    test('finds カード from hiragana with long vowel mark (かーど)', () async {
      expect(await search('かーど'), contains('カード'));
    });

    test('finds カード from hiragana with doubled vowel (かあど)', () async {
      expect(await search('かあど'), contains('カード'));
    });

    test('finds カード from katakana (カード) — regression', () async {
      expect(await search('カード'), contains('カード'));
    });

    test('finds コーヒー from romaji (koohii)', () async {
      expect(await search('koohii'), contains('コーヒー'));
    });

    test('finds カメラ from romaji without long vowels (kamera)', () async {
      expect(await search('kamera'), contains('カメラ'));
    });

    test('finds パーティー from romaji (pa-thi-)', () async {
      expect(await search('pa-thi-'), contains('パーティー'));
    });
  });
}
