import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';

String normalizeVocabularyQuery(String value) => value.trim().toLowerCase();

bool matchesVocabularyQuery(SavedWord word, String query) {
  final normalizedQuery = normalizeVocabularyQuery(query);
  if (normalizedQuery.isEmpty) return true;

  final definitionText = GlossaryParser.parse(word.glossaries).join('\n');
  return [
    word.expression,
    word.reading,
    definitionText,
    word.sentenceContext,
  ].any((text) => text.toLowerCase().contains(normalizedQuery));
}

List<SavedWord> filterVocabularyWords(Iterable<SavedWord> words, String query) {
  final normalizedQuery = normalizeVocabularyQuery(query);
  if (normalizedQuery.isEmpty) return words.toList(growable: false);
  return words
      .where((word) => matchesVocabularyQuery(word, normalizedQuery))
      .toList(growable: false);
}
