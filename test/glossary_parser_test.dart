import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';

import 'shared/yomitan_glossary_fixtures.dart';

void main() {
  group('GlossaryParser — Yomitan dictionaries', () {
    // Every check reads the stored item and a pre-1.47 row's JSON text and
    // expects one answer.
    List<String> parse(String item) {
      final legacy = GlossaryParser.parse(jsonEncode([item]));
      expect(GlossaryParser.parse(jsonEncode([stored(item)])), legacy);
      return legacy;
    }

    String search(String item) {
      final legacy = GlossaryParser.searchTextFromItems([item]);
      expect(GlossaryParser.searchTextFromItems([stored(item)]), legacy);
      expect(GlossaryParser.searchText(jsonEncode([stored(item)])), legacy);
      return legacy;
    }

    test('JMdict search text stays as before; plain text reads in lines', () {
      // Search ranking (whole-gloss lines, headline gloss) is tuned on this
      // output, so Jitendex/Wiktionary rules must not touch JMdict's keys,
      // and display-only changes (inline runs as one line) must not reach
      // it either: a change would need every dictionary re-indexed.
      const cases = <String, (List<String>, String)>{
        jmdictReferences: (
          ['  ▸ repetition mark in katakana\n  ▸ see: 一の字点 kana iteration mark'],
          'repetition mark in katakana\nsee:\n一の字点\nkana iteration mark',
        ),
        jmdictInfoGlossary: (
          ['  ▸ voiced repetition mark in katakana'],
          'voiced repetition mark in katakana',
        ),
        jmdictFormsTable: (['〃\nおなじ\n㊒\nおなじく\n㊒'], '〃\nおなじ\n㊒\nおなじく\n㊒'),
        jmdictNotes: (
          ['  ▸ circle\n  ▸ sometimes used for zero\n  ▸ see: 丸（まる） 1. circle'],
          'circle\nsometimes used for zero\nsee:\n丸\n（\nまる\n）\n1. circle',
        ),
        jmdictSourceLanguages: (
          [
            '  ▸ bitch\n  ▸ witch\n  ▸ ugly woman\n  ▸ dog\n  ▸ Portuguese: espada',
          ],
          'bitch\nwitch\nugly woman\ndog\nportuguese:\nespada',
        ),
        jmdictAntonyms: (
          ['  ▸ urban\n  ▸ antonym: ルーラル rural'],
          'urban\nantonym:\nルーラル\nrural',
        ),
      };
      for (final MapEntry(key: item, value: (plain, searchText))
          in cases.entries) {
        expect(parse(item), plain);
        expect(search(item), searchText);
      }
    });

    test('inline children run together; br and blocks break the line', () {
      String structured(Object content) =>
          jsonEncode({'type': 'structured-content', 'content': content});

      // A bracketed note before the gloss (円柱) is one line, not "〔", the
      // note and "〕…" on three; the search index keeps one line per node.
      final bracketed = structured([
        '〔',
        {'tag': 'span', 'content': '数'},
        '〕a cylinder',
      ]);
      expect(parse(bracketed), ['〔数〕a cylinder']);
      expect(search(bracketed), '〔\n数\n〕a cylinder');

      final mixed = structured([
        {'tag': 'br'},
        'see ',
        {
          'tag': 'a',
          'href': '?query=丸',
          'content': {
            'tag': 'ruby',
            'content': [
              '丸',
              {'tag': 'rt', 'content': 'まる'},
            ],
          },
        },
        {'tag': 'br'},
        'second line',
        {'tag': 'div', 'content': 'a block'},
        'after the block',
        {'tag': 'br'},
      ]);
      expect(parse(mixed), ['see 丸\nsecond line\na block\nafter the block']);
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

    test('a Jitendex redirect names the entry it points to', () {
      for (final item in [jitendexRedirect, stored(jitendexRedirect)]) {
        expect(GlossaryParser.redirectTarget(jsonEncode([item])), (
          expression: '労働相',
          reading: 'ろうどうしょう',
        ));
      }
      // Glossaries with text of their own, or unreadable ones, point nowhere.
      expect(GlossaryParser.redirectTarget(jsonEncode([jitendexTaberu])), null);
      expect(GlossaryParser.redirectTarget('["to eat"]'), null);
      expect(GlossaryParser.redirectTarget('[{"broken'), null);
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
      expect(parse(text), ['a meaning']);
      expect(parse(image), isEmpty);
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
      expect(GlossaryParser.parse(jsonEncode([jsonDecode(jsonObj)])), [
        jsonObj,
      ]);
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

    test('structured content with nothing in it is left out', () {
      final structured = jsonEncode({
        'type': 'structured-content',
        'content': null,
      });
      final glossaries = jsonEncode([structured, 'to run']);
      final result = GlossaryParser.parse(glossaries);
      // As on screen: nothing, rather than raw JSON in an Anki card.
      expect(result, ['to run']);
    });
  });
}
