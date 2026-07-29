import 'dart:convert';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';

class KanjiEntryDisplayData {
  final List<String> onyomi;
  final List<String> kunyomi;

  const KanjiEntryDisplayData({
    this.onyomi = const [],
    this.kunyomi = const [],
  });

  bool get hasReadings => onyomi.isNotEmpty || kunyomi.isNotEmpty;
}

String encodeKanjiReadings(List<String> readings) {
  if (readings.isEmpty) return '';
  return jsonEncode(readings);
}

List<String> decodeKanjiReadings(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
  } catch (_) {
    // Fall back to tokenizing the raw string below.
  }

  return splitKanjiReadingTokens(trimmed);
}

List<String> splitKanjiReadingTokens(String raw) {
  return raw
      .split(RegExp(r'[\s,、;；/／]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

KanjiEntryDisplayData? parseKanjiEntryDisplayData({
  required DictionaryEntry entry,
  required String dictionaryName,
}) {
  if (_hasStoredKanjiMetadata(entry)) {
    final stored = KanjiEntryDisplayData(
      onyomi: decodeKanjiReadings(entry.kanjiOnyomi),
      kunyomi: decodeKanjiReadings(entry.kanjiKunyomi),
    );
    if (stored.hasReadings || entry.entryKind == DictionaryEntryKinds.kanji) {
      return stored.hasReadings
          ? stored
          : _parseLegacyKanjiReadings(entry.reading);
    }
  }

  if (!_isDownloadedKanjidicDictionary(dictionaryName) ||
      !_isSingleKanji(entry.expression)) {
    return null;
  }

  return _parseLegacyKanjiReadings(entry.reading);
}

bool _hasStoredKanjiMetadata(DictionaryEntry entry) {
  return entry.entryKind == DictionaryEntryKinds.kanji ||
      entry.kanjiOnyomi.isNotEmpty ||
      entry.kanjiKunyomi.isNotEmpty;
}

KanjiEntryDisplayData? _parseLegacyKanjiReadings(String reading) {
  final tokens = splitKanjiReadingTokens(reading);
  if (tokens.isEmpty) return null;

  final onyomi = <String>[];
  final kunyomi = <String>[];

  for (final token in tokens) {
    if (_isKatakanaReadingToken(token)) {
      onyomi.add(token);
      continue;
    }
    if (_isHiraganaReadingToken(token)) {
      kunyomi.add(token);
      continue;
    }
    return null;
  }

  if (onyomi.isEmpty && kunyomi.isEmpty) return null;
  return KanjiEntryDisplayData(onyomi: onyomi, kunyomi: kunyomi);
}

bool _isDownloadedKanjidicDictionary(String dictionaryName) {
  return dictionaryName.startsWith('KANJIDIC');
}

bool _isSingleKanji(String expression) {
  final runes = expression.runes;
  return runes.length == 1 && isKanji(runes.single);
}

bool _isKatakanaReadingToken(String token) {
  return token.runes.every(isKatakana);
}

bool _isHiraganaReadingToken(String token) {
  // U+002E: kanjidic readings use "." to mark the okurigana boundary.
  return token.runes.every((rune) => isHiragana(rune) || rune == 0x002E);
}
