import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

/// Build a [WordIdentification] from hand-crafted tokens for testing.
WordIdentification buildIdentification({
  required List<TokenInfo> tokens,
  required int tappedIndex,
  String sentenceContext = 'テスト文。',
}) {
  final tapped = tokens[tappedIndex];
  return WordIdentification(
    result: WordLookupResult(
      surfaceForm: tapped.surface,
      dictionaryForm: tapped.dictionaryForm,
      reading: tapped.reading,
      sentenceContext: sentenceContext,
      tokenStartOffset: tapped.startInText,
    ),
    alignedTokens: tokens,
    tappedTokenIndex: tappedIndex,
  );
}

/// Create contiguous tokens from a list of (surface, reading, dictForm) tuples
/// starting at [startOffset].
List<TokenInfo> makeContiguousTokens(
  List<(String surface, String reading, String dictForm)> defs, {
  int startOffset = 0,
}) {
  final tokens = <TokenInfo>[];
  var offset = startOffset;
  for (final (surface, reading, dictForm) in defs) {
    tokens.add(TokenInfo(
      surface: surface,
      dictionaryForm: dictForm,
      reading: reading,
      pos: '名詞',
      startInText: offset,
    ));
    offset += surface.length;
  }
  return tokens;
}

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;
  late DictionaryQueryService queryService;
  late CompoundWordResolver resolver;
  late int enabledDictId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);
    resolver = CompoundWordResolver(queryService);

    enabledDictId = await repo.insertDictionary('TestDict');

    await repo.batchInsertEntries([
      // Compound entries
      DictionaryEntriesCompanion.insert(
        expression: '国立大学',
        reading: const Value('こくりつだいがく'),
        glossaries: jsonEncode(['national university']),
        dictionaryId: enabledDictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '国立大学院',
        reading: const Value('こくりつだいがくいん'),
        glossaries: jsonEncode(['national graduate school']),
        dictionaryId: enabledDictId,
      ),
      // Single-token entries
      DictionaryEntriesCompanion.insert(
        expression: '国立',
        reading: const Value('こくりつ'),
        glossaries: jsonEncode(['national']),
        dictionaryId: enabledDictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '大学',
        reading: const Value('だいがく'),
        glossaries: jsonEncode(['university']),
        dictionaryId: enabledDictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat']),
        dictionaryId: enabledDictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '猫',
        reading: const Value('ネコ'),
        glossaries: jsonEncode(['cat']),
        dictionaryId: enabledDictId,
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Compound found (greedy longest-match) ──────────────────────

  group('CompoundWordResolver — compound found', () {
    test('returns compound when dictionary has a multi-token match', () async {
      // "国立大学に" → tokens: [国立, 大学, に]
      final tokens = makeContiguousTokens([
        ('国立', 'こくりつ', '国立'),
        ('大学', 'だいがく', '大学'),
        ('に', 'ニ', 'に'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '国立大学');
      expect(result.tokenCount, 2);
      expect(result.dictionaryForm, '国立大学');
    });

    test('prefers longer match over shorter', () async {
      // "国立大学院" → tokens: [国立, 大学, 院]
      final tokens = makeContiguousTokens([
        ('国立', 'こくりつ', '国立'),
        ('大学', 'だいがく', '大学'),
        ('院', 'いん', '院'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      // Should find "国立大学院" (3 tokens) over "国立大学" (2 tokens)
      expect(result.surfaceForm, '国立大学院');
      expect(result.tokenCount, 3);
    });

    test('concatenates reading from all matched tokens', () async {
      final tokens = makeContiguousTokens([
        ('国立', 'こくりつ', '国立'),
        ('大学', 'だいがく', '大学'),
        ('に', 'ニ', 'に'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.reading, 'こくりつだいがく');
    });

    test('dictionaryForm equals surfaceForm for compounds', () async {
      final tokens = makeContiguousTokens([
        ('国立', 'こくりつ', '国立'),
        ('大学', 'だいがく', '大学'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.dictionaryForm, result.surfaceForm);
    });
  });

  // ── Deinflected compound match ──────────────────────────────────

  group('CompoundWordResolver — deinflected compound', () {
    test('matches compound via deinflection (te-form → dictionary form)',
        () async {
      // 行く is in the dictionary; 行って is not.
      // MeCab splits 行ってあげて into [行っ, て, あげ, て].
      // The resolver should try 行って, deinflect it to 行く, and match.
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '行く',
          reading: const Value('いく'),
          glossaries: jsonEncode(['to go']),
          dictionaryId: enabledDictId,
        ),
      ]);

      final tokens = makeContiguousTokens([
        ('行っ', 'イッ', '行う'),
        ('て', 'テ', 'て'),
        ('あげ', 'アゲ', 'あげる'),
        ('て', 'テ', 'て'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '行って');
      expect(result.dictionaryForm, '行く');
      expect(result.tokenCount, 2);
    });

    test('prefers exact compound match over deinflected match', () async {
      // If the compound surface itself is in the dictionary, use it directly.
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '行って',
          reading: const Value('いって'),
          glossaries: jsonEncode(['te-form of to go']),
          dictionaryId: enabledDictId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '行く',
          reading: const Value('いく'),
          glossaries: jsonEncode(['to go']),
          dictionaryId: enabledDictId,
        ),
      ]);

      final tokens = makeContiguousTokens([
        ('行っ', 'イッ', '行う'),
        ('て', 'テ', 'て'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      // Exact match should win — dictionaryForm equals surfaceForm.
      expect(result.surfaceForm, '行って');
      expect(result.dictionaryForm, '行って');
      expect(result.tokenCount, 2);
    });

    test('deinflected compound preserves reading from tokens', () async {
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: jsonEncode(['to eat']),
          dictionaryId: enabledDictId,
        ),
      ]);

      // 食べて → deinflects to 食べる
      final tokens = makeContiguousTokens([
        ('食べ', 'タベ', '食べる'),
        ('て', 'テ', 'て'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '食べて');
      expect(result.dictionaryForm, '食べる');
      expect(result.reading, 'タベテ'); // concatenated from tokens
      expect(result.tokenCount, 2);
    });

    test('falls back to single token when no deinflection matches', () async {
      // No entry for any deinflection of ゴロゴロして
      final tokens = makeContiguousTokens([
        ('ゴロゴロ', 'ゴロゴロ', 'ゴロゴロ'),
        ('し', 'シ', 'する'),
        ('て', 'テ', 'て'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, 'ゴロゴロ');
      expect(result.tokenCount, 1);
    });
  });

  // ── Falls back to single token ─────────────────────────────────

  group('CompoundWordResolver — single token fallback', () {
    test('returns single token when no compound match exists', () async {
      final tokens = makeContiguousTokens([
        ('食べる', 'たべる', '食べる'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '食べる');
      expect(result.tokenCount, 1);
      expect(result.dictionaryForm, '食べる');
    });

    test('returns single token when only it has a dictionary match', () async {
      // "猫が好き" — dictionary has "猫" but not "猫が" or "猫が好き"
      final tokens = makeContiguousTokens([
        ('猫', 'ネコ', '猫'),
        ('が', 'ガ', 'が'),
        ('好き', 'スキ', '好き'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '猫');
      expect(result.tokenCount, 1);
    });

    test('preserves sentenceContext from original result', () async {
      const context = '猫が大好きです。';
      final tokens = makeContiguousTokens([
        ('猫', 'ネコ', '猫'),
      ]);
      final id = buildIdentification(
        tokens: tokens,
        tappedIndex: 0,
        sentenceContext: context,
      );

      final result = await resolver.resolve(id);

      expect(result.sentenceContext, context);
    });

    test('preserves tokenStartOffset from original result', () async {
      final tokens = makeContiguousTokens([
        ('食べる', 'たべる', '食べる'),
      ], startOffset: 10);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.tokenStartOffset, 10);
    });
  });

  // ── Non-contiguous / unaligned tokens ──────────────────────────

  group('CompoundWordResolver — non-contiguous tokens', () {
    test('falls back when there is a gap between tokens', () async {
      // Tokens are not contiguous: 国立 at 0, 大学 at 5 (gap at 2-4)
      final tokens = [
        const TokenInfo(
          surface: '国立',
          dictionaryForm: '国立',
          reading: 'こくりつ',
          pos: '名詞',
          startInText: 0,
        ),
        const TokenInfo(
          surface: '大学',
          dictionaryForm: '大学',
          reading: 'だいがく',
          pos: '名詞',
          startInText: 5, // gap! should be 2
        ),
      ];
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '国立');
      expect(result.tokenCount, 1);
    });

    test('falls back when token has startInText == -1 (unaligned)', () async {
      final tokens = [
        const TokenInfo(
          surface: '国立',
          dictionaryForm: '国立',
          reading: 'こくりつ',
          pos: '名詞',
          startInText: 0,
        ),
        const TokenInfo(
          surface: '大学',
          dictionaryForm: '大学',
          reading: 'だいがく',
          pos: '名詞',
          startInText: -1, // unaligned
        ),
      ];
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.surfaceForm, '国立');
      expect(result.tokenCount, 1);
    });
  });

  // ── Edge cases ─────────────────────────────────────────────────

  group('CompoundWordResolver — edge cases', () {
    test('handles tapped token at end of list (no subsequent tokens)', () async {
      final tokens = makeContiguousTokens([
        ('食べる', 'たべる', '食べる'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      expect(result.tokenCount, 1);
      expect(result.surfaceForm, '食べる');
    });

    test('maxTokenSpan limits compound length to 5 tokens', () async {
      // Create 6 contiguous tokens that form a "word" in the dictionary
      final sixTokenCompound = '一二三四五六';
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: sixTokenCompound,
          reading: const Value('いちにさんしごろく'),
          glossaries: jsonEncode(['six-token compound']),
          dictionaryId: enabledDictId,
        ),
        // Also add a 5-token version
        DictionaryEntriesCompanion.insert(
          expression: '一二三四五',
          reading: const Value('いちにさんしご'),
          glossaries: jsonEncode(['five-token compound']),
          dictionaryId: enabledDictId,
        ),
      ]);

      final tokens = makeContiguousTokens([
        ('一', 'いち', '一'),
        ('二', 'に', '二'),
        ('三', 'さん', '三'),
        ('四', 'し', '四'),
        ('五', 'ご', '五'),
        ('六', 'ろく', '六'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      // maxTokenSpan is 5, so it should find "一二三四五" (5 tokens)
      // not "一二三四五六" (6 tokens)
      expect(result.surfaceForm, '一二三四五');
      expect(result.tokenCount, 5);
    });

    test('disabled dictionary entries are not matched as compounds', () async {
      // Create a disabled dictionary with a compound entry
      final disabledDictId = await repo.insertDictionary('DisabledDict');
      await repo.toggleDictionary(disabledDictId, isEnabled: false);

      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '特別価格',
          reading: const Value('とくべつかかく'),
          glossaries: jsonEncode(['special price']),
          dictionaryId: disabledDictId,
        ),
      ]);

      final tokens = makeContiguousTokens([
        ('特別', 'とくべつ', '特別'),
        ('価格', 'かかく', '価格'),
      ]);
      final id = buildIdentification(tokens: tokens, tappedIndex: 0);

      final result = await resolver.resolve(id);

      // Should fall back to single token since compound is in disabled dict
      expect(result.surfaceForm, '特別');
      expect(result.tokenCount, 1);
    });
  });
}
