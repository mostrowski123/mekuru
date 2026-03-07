import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/kanji_reading_parser.dart';

DictionaryEntry _buildEntry({
  String expression = '日',
  String reading = '',
  String entryKind = DictionaryEntryKinds.regular,
  String kanjiOnyomi = '',
  String kanjiKunyomi = '',
}) {
  return DictionaryEntry(
    id: 1,
    expression: expression,
    reading: reading,
    entryKind: entryKind,
    kanjiOnyomi: kanjiOnyomi,
    kanjiKunyomi: kanjiKunyomi,
    glossaries: '[]',
    dictionaryId: 1,
  );
}

void main() {
  group('parseKanjiEntryDisplayData', () {
    test('uses explicit stored kanji metadata when present', () {
      final data = parseKanjiEntryDisplayData(
        entry: _buildEntry(
          reading: 'ニチ ジツ ひ か',
          entryKind: DictionaryEntryKinds.kanji,
          kanjiOnyomi: jsonEncode(['ニチ', 'ジツ']),
          kanjiKunyomi: jsonEncode(['ひ', 'か']),
        ),
        dictionaryName: 'Custom Kanji Dictionary',
      );

      expect(data, isNotNull);
      expect(data!.onyomi, ['ニチ', 'ジツ']);
      expect(data.kunyomi, ['ひ', 'か']);
    });

    test('falls back for legacy downloaded KANJIDIC rows', () {
      final data = parseKanjiEntryDisplayData(
        entry: _buildEntry(reading: 'ニチ ジツ ひ か'),
        dictionaryName: 'KANJIDIC English',
      );

      expect(data, isNotNull);
      expect(data!.onyomi, ['ニチ', 'ジツ']);
      expect(data.kunyomi, ['ひ', 'か']);
    });

    test('treats single-script legacy rows as a single reading bucket', () {
      final data = parseKanjiEntryDisplayData(
        entry: _buildEntry(reading: 'ひ'),
        dictionaryName: 'KANJIDIC English',
      );

      expect(data, isNotNull);
      expect(data!.onyomi, isEmpty);
      expect(data.kunyomi, ['ひ']);
    });

    test('returns null for ambiguous legacy rows', () {
      final data = parseKanjiEntryDisplayData(
        entry: _buildEntry(reading: 'ニチabc'),
        dictionaryName: 'KANJIDIC English',
      );

      expect(data, isNull);
    });

    test('does not apply fallback to non-KANJIDIC regular entries', () {
      final data = parseKanjiEntryDisplayData(
        entry: _buildEntry(reading: 'ニチ ジツ ひ か'),
        dictionaryName: 'General Dictionary',
      );

      expect(data, isNull);
    });
  });
}
