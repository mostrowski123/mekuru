import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/free_books/data/catalog_counts.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/services/aozora_catalog.dart';

const _authors = [
  ['太宰 治', 'だざい おさむ'],
  ['夏目 漱石', 'なつめ そうせき'],
  ['宮沢 賢治', 'みやざわ けんじ'],
  ['紫式部', 'むらさきしきぶ'],
];

Map<String, Object?> _work({
  required int id,
  required String title,
  String? subtitle,
  String reading = '',
  required int author,
  String genre = 'fic',
  String spelling = 'm',
  int chars = 1000,
  int level = 3,
  int popularity = 0,
}) => {
  'i': id,
  't': title,
  's': ?subtitle,
  'r': reading,
  'a': author,
  'x': '000035/files/${id}_1.html',
  'g': genre,
  'o': spelling,
  'n': chars,
  'l': level,
  'p': popularity,
};

void main() {
  final works = parseAozoraCatalog(
    jsonEncode({
      'authors': _authors,
      'works': [
        _work(
          id: 1567,
          title: '走れメロス',
          reading: 'はしれメロス',
          author: 0,
          chars: 9913,
          level: 3,
          popularity: 2549758,
        ),
        _work(
          id: 773,
          title: 'こころ',
          reading: 'こころ',
          author: 1,
          chars: 170000,
          level: 2,
          popularity: 2000000,
        ),
        _work(
          id: 628,
          title: '注文の多い料理店',
          reading: 'ちゅうもんのおおいりょうりてん',
          author: 2,
          genre: 'kid',
          chars: 6000,
          level: 4,
          popularity: 900000,
        ),
        _work(
          id: 5016,
          title: '源氏物語',
          subtitle: '桐壺',
          reading: 'げんじものがたり',
          author: 3,
          spelling: 'k',
          chars: 30000,
          level: 0,
        ),
      ],
    }),
  );
  AozoraWork byId(int id) => works.firstWhere((w) => w.id == id);

  /// Ids of the works [query] selects, in order.
  List<int> run(
    AozoraQuery query, {
    double charsPerMinute = defaultReadingPaceCharsPerMinute,
    bool Function(AozoraWork work)? isInLibrary,
  }) => [
    for (final w in filterAndSortWorks(
      works,
      query,
      charsPerMinute: charsPerMinute,
      isInLibrary: isInLibrary,
    ))
      w.id,
  ];

  group('parseAozoraCatalog', () {
    test('reads every field', () {
      final melos = byId(1567);
      expect(melos.title, '走れメロス');
      expect(melos.author, '太宰 治');
      expect(melos.authorReading, 'だざい おさむ');
      expect(melos.genre, AozoraGenre.fiction);
      expect(melos.spelling, AozoraSpelling.modern);
      expect(melos.charCount, 9913);
      expect(melos.jlptEstimate, 3);
      expect(
        melos.cardUrl.toString(),
        'https://www.aozora.gr.jp/cards/000035/card1567.html',
      );
    });

    test('displayTitle keeps the parts of a multi-part work apart', () {
      expect(byId(5016).displayTitle, '源氏物語 桐壺');
      expect(byId(1567).displayTitle, '走れメロス');
    });

    test('the bundled catalog parses and matches its generated count', () {
      final bundled = parseAozoraCatalog(
        File('assets/free_books/aozora.json').readAsStringSync(),
      );
      expect(bundled, hasLength(aozoraWorkCount));
      expect(bundled.map((w) => w.id).toSet(), hasLength(aozoraWorkCount));
    });
  });

  group('search', () {
    List<int> search(String text) => run(AozoraQuery(text: text));

    test('matches titles, readings and authors', () {
      expect(search('メロス'), [1567]);
      expect(search('はしれ'), [1567]);
      expect(search('漱石'), [773]);
    });

    test('ignores the space between family and given names', () {
      expect(search('太宰治'), [1567]);
    });

    test('matches romaji against the kana readings', () {
      expect(search('dazai'), [1567]);
      expect(search('Miyazawa'), [628]);
      expect(search('hashire'), [1567]);
    });

    test('folds katakana so either kana script matches', () {
      expect(search('ハシレ'), [1567]);
    });

    test('an empty query matches everything', () {
      expect(search(''), hasLength(4));
    });
  });

  group('filters', () {
    test('level, genre and spelling', () {
      expect(run(const AozoraQuery(levels: {3, 4})), [1567, 628]);
      expect(run(const AozoraQuery(genres: {AozoraGenre.children})), [628]);
      expect(run(const AozoraQuery(spellings: {AozoraSpelling.oldKana})), [
        5016,
      ]);
    });

    test('length buckets follow the reading pace', () {
      const quick = AozoraQuery(lengths: {AozoraLength.under10Minutes});
      // 6,000 characters: 24 min at 250/min, under 9 min at 700/min (while
      // the 9,913-character work still takes over 14).
      expect(run(quick), isEmpty);
      expect(run(quick, charsPerMinute: 700), [628]);
    });

    test('hide in library uses the given predicate', () {
      expect(
        run(
          const AozoraQuery(hideInLibrary: true),
          isInLibrary: (w) => w.id == 773,
        ),
        [1567, 628, 5016],
      );
    });

    test('easy picks are the easy levels in modern spelling', () {
      expect(run(AozoraQuery.easyPicks), [1567, 628]);
    });

    test('cleared keeps search and sort but drops filters', () {
      final query = AozoraQuery.easyPicks.copyWith(
        text: 'x',
        sort: AozoraSort.title,
      );
      final cleared = query.cleared();
      expect(cleared.hasFilters, isFalse);
      expect(cleared.text, 'x');
      expect(cleared.sort, AozoraSort.title);
    });
  });

  group('sort', () {
    List<int> sorted(AozoraSort sort) => run(AozoraQuery(sort: sort));

    test('popular puts the most-read first', () {
      expect(sorted(AozoraSort.popular), [1567, 773, 628, 5016]);
    });

    test('easiest and hardest put beyond-N1 last and first', () {
      expect(sorted(AozoraSort.easiest), [628, 1567, 773, 5016]);
      expect(sorted(AozoraSort.hardest), [5016, 773, 1567, 628]);
    });

    test('shortest and longest by characters', () {
      expect(sorted(AozoraSort.shortest), [628, 1567, 5016, 773]);
      expect(sorted(AozoraSort.longest), [773, 5016, 1567, 628]);
    });

    test('title and author in kana order', () {
      expect(sorted(AozoraSort.title), [5016, 773, 628, 1567]);
      expect(sorted(AozoraSort.author), [1567, 773, 628, 5016]);
    });
  });
}
