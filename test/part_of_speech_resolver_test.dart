import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/part_of_speech_resolver.dart';

DictionaryEntry _buildEntry({
  String definitionTags = '',
  String rules = '',
  String termTags = '',
}) {
  return DictionaryEntry(
    id: 1,
    expression: '食べる',
    reading: 'たべる',
    entryKind: DictionaryEntryKinds.regular,
    kanjiOnyomi: '',
    kanjiKunyomi: '',
    definitionTags: definitionTags,
    rules: rules,
    termTags: termTags,
    glossaries: '["to eat"]',
    dictionaryId: 1,
  );
}

void main() {
  group('PartOfSpeechResolver.resolveLabels', () {
    test('maps common noun, adjective, and verb tags to friendly labels', () {
      final labels = PartOfSpeechResolver.resolveLabels(
        _buildEntry(definitionTags: 'n adj-i', rules: 'v1 vt'),
      );

      expect(labels, [
        'Ichidan verb',
        'Transitive verb',
        'Noun',
        'I-adjective',
      ]);
    });

    test(
      'keeps useful verb distinctions for godan, suru, and intransitive',
      () {
        final labels = PartOfSpeechResolver.resolveLabels(
          _buildEntry(rules: 'v5k-s vs-s vi'),
        );

        expect(labels, ['Godan verb', 'Suru verb', 'Intransitive verb']);
      },
    );

    test('deduplicates mixed inputs and suppresses obvious non-pos tags', () {
      final labels = PartOfSpeechResolver.resolveLabels(
        _buildEntry(
          definitionTags: 'adv-to nf12',
          rules: 'vt vt',
          termTags: 'P custom-verb-tag',
        ),
      );

      expect(labels, ['Transitive verb', 'To-adverb', 'custom-verb-tag']);
    });
  });
}
