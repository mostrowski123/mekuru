import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// All available data for creating an Anki note from a looked-up word.
class AnkiNoteData {
  final String expression;
  final String reading;
  final String glossaries;
  final String dictionaryName;
  final int? frequencyRank;
  final String? sentenceContext;

  /// Machine translation of [sentenceContext], when a field asks for it.
  final String? sentenceTranslation;
  final List<PitchAccentResult> pitchAccents;

  const AnkiNoteData({
    required this.expression,
    required this.reading,
    required this.glossaries,
    required this.dictionaryName,
    this.frequencyRank,
    this.sentenceContext,
    this.sentenceTranslation,
    this.pitchAccents = const [],
  });
}

/// Stands in for a looked-up word when previewing field mappings, so every
/// data source shows a value.
const exampleAnkiNoteData = AnkiNoteData(
  expression: '食べる',
  reading: 'たべる',
  glossaries: '["to eat"]',
  dictionaryName: 'Jitendex',
  frequencyRank: 120,
  sentenceContext: '毎朝パンを食べる。',
  sentenceTranslation: 'I eat bread every morning.',
  pitchAccents: [
    PitchAccentResult(
      reading: 'たべる',
      downstepPosition: 2,
      dictionaryName: 'Example',
      dictionaryId: 0,
    ),
  ],
);
