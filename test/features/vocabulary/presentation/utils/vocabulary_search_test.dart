import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/presentation/utils/vocabulary_search.dart';

SavedWord _word({
  required int id,
  required String expression,
  required String reading,
  required List<String> definitions,
}) {
  return SavedWord(
    id: id,
    expression: expression,
    reading: reading,
    glossaries: jsonEncode(definitions),
    sentenceContext: '',
    dateAdded: DateTime(2026, 3, 8),
  );
}

void main() {
  test('matches expression, reading, and definition text', () {
    final word = _word(
      id: 1,
      expression: '食べる',
      reading: 'たべる',
      definitions: ['to eat', 'to consume'],
    );

    expect(matchesVocabularyQuery(word, '食べる'), isTrue);
    expect(matchesVocabularyQuery(word, 'たべる'), isTrue);
    expect(matchesVocabularyQuery(word, 'consume'), isTrue);
    expect(matchesVocabularyQuery(word, 'swim'), isFalse);
  });
}
