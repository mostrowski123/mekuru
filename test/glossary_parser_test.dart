import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';

void main() {
  group('GlossaryParser', () {
    test('parses plain string definitions', () {
      final glossaries = jsonEncode(['to eat', 'to consume']);
      final result = GlossaryParser.parse(glossaries);
      expect(result, ['to eat', 'to consume']);
    });

    test('extracts text from structured-content object', () {
      final glossaries = jsonEncode([
        jsonEncode({
          'type': 'structured-content',
          'content': 'a simple definition',
        }),
      ]);
      final result = GlossaryParser.parse(glossaries);
      expect(result, hasLength(1));
      expect(result[0], 'a simple definition');
    });

    test('extracts text from deeply nested structured-content', () {
      final structuredContent = jsonEncode({
        'type': 'structured-content',
        'content': [
          'A case; circumstances',
          {
            'tag': 'ul',
            'content': [
              {
                'tag': 'li',
                'content': 'こういう仕儀ですから',
              },
              {
                'tag': 'li',
                'content': 'Such being the case',
              },
            ],
          },
        ],
      });
      final glossaries = jsonEncode([structuredContent]);
      final result = GlossaryParser.parse(glossaries);
      expect(result, hasLength(1));
      expect(result[0], contains('A case; circumstances'));
      expect(result[0], contains('こういう仕儀ですから'));
      expect(result[0], contains('Such being the case'));
    });

    test('handles mixed plain and structured-content items', () {
      final glossaries = jsonEncode([
        'plain meaning',
        jsonEncode({
          'type': 'structured-content',
          'content': 'rich meaning',
        }),
        'another plain',
      ]);
      final result = GlossaryParser.parse(glossaries);
      expect(result, hasLength(3));
      expect(result[0], 'plain meaning');
      expect(result[1], 'rich meaning');
      expect(result[2], 'another plain');
    });

    test('returns raw string for non-structured-content JSON objects', () {
      final jsonObj = jsonEncode({'someKey': 'someValue'});
      final glossaries = jsonEncode([jsonObj]);
      final result = GlossaryParser.parse(glossaries);
      expect(result, hasLength(1));
      // Non-structured-content JSON should be returned as-is
      expect(result[0], jsonObj);
    });

    test('handles empty glossary list', () {
      final glossaries = jsonEncode([]);
      final result = GlossaryParser.parse(glossaries);
      expect(result, isEmpty);
    });

    test('handles malformed JSON gracefully', () {
      final result = GlossaryParser.parse('not valid json');
      expect(result, ['not valid json']);
    });

    test('formats li tags with bullet points', () {
      final structured = jsonEncode({
        'type': 'structured-content',
        'content': [
          {
            'tag': 'ul',
            'content': [
              {'tag': 'li', 'content': 'first item'},
              {'tag': 'li', 'content': 'second item'},
            ],
          },
        ],
      });
      final glossaries = jsonEncode([structured]);
      final result = GlossaryParser.parse(glossaries);
      expect(result[0], contains('\u25b8 first item'));
      expect(result[0], contains('\u25b8 second item'));
    });

    test('handles structured-content with nested content arrays', () {
      final structured = jsonEncode({
        'type': 'structured-content',
        'content': [
          'header text',
          {
            'tag': 'div',
            'content': [
              'inner text',
              {'tag': 'span', 'content': 'span text'},
            ],
          },
        ],
      });
      final glossaries = jsonEncode([structured]);
      final result = GlossaryParser.parse(glossaries);
      expect(result[0], contains('header text'));
      expect(result[0], contains('inner text'));
      expect(result[0], contains('span text'));
    });

    test('handles null content in structured objects', () {
      final structured = jsonEncode({
        'type': 'structured-content',
        'content': null,
      });
      final glossaries = jsonEncode([structured]);
      final result = GlossaryParser.parse(glossaries);
      // Falls back to raw JSON since extracted text is empty
      expect(result, hasLength(1));
      expect(result[0], contains('structured-content'));
    });
  });
}
