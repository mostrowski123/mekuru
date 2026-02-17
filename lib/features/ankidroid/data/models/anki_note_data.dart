import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// All available data for creating an Anki note from a looked-up word.
class AnkiNoteData {
  final String expression;
  final String reading;
  final String glossaries;
  final String dictionaryName;
  final int? frequencyRank;
  final String? sentenceContext;
  final List<PitchAccentResult> pitchAccents;

  const AnkiNoteData({
    required this.expression,
    required this.reading,
    required this.glossaries,
    required this.dictionaryName,
    this.frequencyRank,
    this.sentenceContext,
    this.pitchAccents = const [],
  });
}
