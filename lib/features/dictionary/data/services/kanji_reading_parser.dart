import 'dart:convert';

import 'package:mekuru/core/database/database_provider.dart';
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
  final runes = expression.runes.toList(growable: false);
  if (runes.length != 1) return false;

  final rune = runes.single;
  return (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF);
}

bool _isKatakanaReadingToken(String token) {
  for (final rune in token.runes) {
    final isKatakana = (rune >= 0x30A0 && rune <= 0x30FF) || rune == 0x30FC;
    if (!isKatakana) return false;
  }
  return true;
}

bool _isHiraganaReadingToken(String token) {
  for (final rune in token.runes) {
    final isHiragana =
        (rune >= 0x3040 && rune <= 0x309F) || rune == 0x30FC || rune == 0x002E;
    if (!isHiragana) return false;
  }
  return true;
}
