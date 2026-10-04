import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';

import 'shared/yomitan_glossary_fixtures.dart';

void main() {
  group('GlossaryParser — Yomitan dictionaries', () {
    List<String> parse(String item) => GlossaryParser.parse(jsonEncode([item]));
    String search(String item) => GlossaryParser.searchTextFromItems([item]);

    test('JMdict plain and search text stay exactly as before', () {
      // Search ranking (whole-gloss lines, headline gloss) is tuned on this
      // output, so Jitendex/Wiktionary rules must not touch JMdict's keys.
      const cases = <String, (List<String>, String)>{
        jmdictReferences: (
          [
            '  ▸ repetition mark in katakana\n  ▸ see: \n一の字点\n kana iteration mark',
          ],
          'repetition mark in katakana\nsee:\n一の字点\nkana iteration mark',
        ),
        jmdictInfoGlossary: (
          ['  ▸ voiced repetition mark in katakana'],
          'voiced repetition mark in katakana',
        ),
        jmdictFormsTable: (['〃\nおなじ\n㊒\nおなじく\n㊒'], '〃\nおなじ\n㊒\nおなじく\n㊒'),
        jmdictNotes: (
          [
            '  ▸ circle\n  ▸ sometimes used for zero\n  ▸ see: \n丸\n（\nまる\n）\n 1. circle',
          ],
          'circle\nsometimes used for zero\nsee:\n丸\n（\nまる\n）\n1. circle',
        ),
        jmdictSourceLanguages: (
          [
            '  ▸ bitch\n  ▸ witch\n  ▸ ugly woman\n  ▸ dog\n  ▸ Portuguese: \nespada',
          ],
          'bitch\nwitch\nugly woman\ndog\nportuguese:\nespada',
        ),
        jmdictAntonyms: (
          ['  ▸ urban\n  ▸ antonym: \nルーラル\n rural'],
          'urban\nantonym:\nルーラル\nrural',
        ),
      };
      for (final MapEntry(key: item, value: (plain, searchText))
          in cases.entries) {
        expect(parse(item), plain);
        expect(search(item), searchText);
      }
    });

    test('a Jitendex entry reads as one marked line per sense', () {
      expect(parse(jitendexTaberu), [
        '① to eat\n② to live on (e.g. a salary); to live off; to subsist on',
      ]);
    });

    test('a one-sense Jitendex entry reads as its glossary line', () {
      expect(parse(jitendexGakkou), ['school']);
      expect(parse(jitendexFormsTable), ['ditto mark']);
      expect(parse(jitendexGraphic), ['Japanese andromeda (Pieris japonica)']);
    });

    test('Jitendex search text holds one gloss per line and nothing else', () {
      expect(
        search(jitendexTaberu),
        'to eat\nto live on (e.g. a salary)\nto live off\nto subsist on',
      );
      expect(search(jitendexGakkou), 'school');
    });

    test('a Jitendex redirect row has no plain text and blank search text', () {
      expect(parse(jitendexRedirect), isEmpty);
      // A single space, not '': the launch-time backfill re-reads every row
      // whose search_text is ''.
      expect(search(jitendexRedirect), ' ');
    });

    test('a Wiktionary entry reads as numbered glosses without examples', () {
      expect(parse(wtyEnglishTaberu), [
        '1. to eat\n2. to make a living\n3. to eat or drink',
      ]);
      expect(
        search(wtyEnglishTaberu),
        'to eat\nto make a living\nto eat or drink',
      );
    });

    test('text glossary items read as their text; image items as nothing', () {
      final text = jsonEncode({'type': 'text', 'text': 'a meaning'});
      final image = jsonEncode({'type': 'image', 'path': 'img/a.png'});

      expect(GlossaryParser.parse(jsonEncode([text, image])), ['a meaning']);
      expect(search(image), ' ');
      expect(GlossaryParser.searchTextFromItems([]), '');
    });
  });

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
              {'tag': 'li', 'content': 'こういう仕儀ですから'},
              {'tag': 'li', 'content': 'Such being the case'},
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
        jsonEncode({'type': 'structured-content', 'content': 'rich meaning'}),
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

    test('shows placeholder for truncated JSON list', () {
      final result = GlossaryParser.parse('["definition one", "defini');
      expect(result, [GlossaryParser.unreadableDefinitionPlaceholder]);
    });

    test('shows placeholder for truncated JSON object', () {
      final result = GlossaryParser.parse('{"type": "structured-co');
      expect(result, [GlossaryParser.unreadableDefinitionPlaceholder]);
    });

    test('shows placeholder for broken JSON with leading whitespace', () {
      final result = GlossaryParser.parse('  [broken');
      expect(result, [GlossaryParser.unreadableDefinitionPlaceholder]);
    });

    test('keeps plain-text passthrough for non-JSON-looking strings', () {
      final result = GlossaryParser.parse('食べる: to eat');
      expect(result, ['食べる: to eat']);
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
