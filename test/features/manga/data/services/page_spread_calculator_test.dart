import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';

/// Pages from a compact spec, one letter per page: `p` portrait, `w` wide,
/// `0` size unknown, and `L`, `R`, `C` portrait pages declared
/// page-spread-left, -right and -center.
List<MokuroPage> _pages(String spec) => [
  for (var i = 0; i < spec.length; i++)
    MokuroPage(
      pageIndex: i,
      imageFileName: 'p$i.jpg',
      imgWidth: spec[i] == 'w' ? 200 : 100,
      imgHeight: switch (spec[i]) {
        'w' => 100,
        '0' => 0,
        _ => 150,
      },
      blocks: const [],
      spread: switch (spec[i]) {
        'L' => MangaPageSpread.left,
        'R' => MangaPageSpread.right,
        'C' => MangaPageSpread.center,
        _ => null,
      },
    ),
];

/// Each spread's pages in reading order.
List<List<int>> _order(List<PageSpread> spreads, {required bool isRtl}) => [
  for (final s in spreads)
    [
      if (isRtl) ...[?s.rightPageIndex, ?s.leftPageIndex],
      if (!isRtl) ...[?s.leftPageIndex, ?s.rightPageIndex],
    ],
];

List<List<int>> _spreads(
  String spec, {
  bool isRtl = true,
  bool? bookRtl,
  bool detectWidePages = true,
  bool shift = false,
}) => _order(
  computeSpreads(
    _pages(spec),
    isRtl: isRtl,
    bookRtl: bookRtl,
    detectWidePages: detectWidePages,
    shift: shift,
  ),
  isRtl: isRtl,
);

void main() {
  group('computeSpreads', () {
    test('returns an empty list for a book without pages', () {
      expect(computeSpreads(const [], isRtl: true), isEmpty);
    });

    test('the cover stands alone, then pages pair up', () {
      expect(_spreads('p'), [
        [0],
      ]);
      expect(_spreads('pp'), [
        [0],
        [1],
      ]);
      expect(_spreads('ppppp'), [
        [0],
        [1, 2],
        [3, 4],
      ]);
      expect(_spreads('pppp'), [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('right to left puts the earlier page on the right', () {
      final spreads = computeSpreads(_pages('ppp'), isRtl: true);
      expect(spreads, const [
        PageSpread(rightPageIndex: 0),
        PageSpread(leftPageIndex: 2, rightPageIndex: 1),
      ]);
    });

    test('left to right puts the earlier page on the left', () {
      final spreads = computeSpreads(_pages('ppp'), isRtl: false);
      expect(spreads, const [
        PageSpread(leftPageIndex: 0),
        PageSpread(leftPageIndex: 1, rightPageIndex: 2),
      ]);
    });

    test('a wide page stands alone and pairing restarts after it', () {
      expect(_spreads('ppppwpp'), [
        [0],
        [1, 2],
        [3],
        [4],
        [5, 6],
      ]);
      expect(_spreads('wppp', isRtl: false), [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('wide pages pair like any other with detection off', () {
      expect(_spreads('ppwp', detectWidePages: false), [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('a page of unknown size is not wide', () {
      expect(_spreads('p00'), [
        [0],
        [1, 2],
      ]);
    });

    test('a declared center page stands alone even with detection off', () {
      expect(_spreads('ppCpp', detectWidePages: false), [
        [0],
        [1],
        [2],
        [3, 4],
      ]);
    });

    test('declared halves pair up: right opens a pair in rtl books', () {
      expect(_spreads('pRLRL'), [
        [0],
        [1, 2],
        [3, 4],
      ]);
      // An undeclared page never takes an opener as its partner.
      expect(_spreads('ppRL'), [
        [0],
        [1],
        [2, 3],
      ]);
      // An opener takes the undeclared page after it.
      expect(_spreads('pLRpp'), [
        [0],
        [1],
        [2, 3],
        [4],
      ]);
    });

    test('left opens a pair in ltr books', () {
      expect(_spreads('pLRLR', isRtl: false), [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('declared halves pair the way the book declares, read either way', () {
      // A right-to-left book read left to right: each right half still
      // opens its pair.
      expect(_spreads('pRLRL', isRtl: false, bookRtl: true), [
        [0],
        [1, 2],
        [3, 4],
      ]);
      // A left-to-right book read right to left.
      expect(_spreads('pLRLR', bookRtl: false), [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('an orphan closer stands alone', () {
      expect(_spreads('pLp'), [
        [0],
        [1],
        [2],
      ]);
    });

    test('shift pairs the cover and moves every pair by one page', () {
      expect(_spreads('ppppp', shift: true), [
        [0, 1],
        [2, 3],
        [4],
      ]);
      expect(_spreads('ppwppp', shift: true), [
        [0, 1],
        [2],
        [3],
        [4, 5],
      ]);
    });

    test('shift swaps which declared half opens a pair', () {
      expect(_spreads('pRLRL', shift: true), [
        [0, 1],
        [2, 3],
        [4],
      ]);
    });

    test('every page is in exactly one spread', () {
      for (final spec in ['p', 'ppp', 'pwpRLpCpp', 'RLRLR', 'LLwRR']) {
        for (final shift in [false, true]) {
          final pages = _spreads(spec, shift: shift).expand((s) => s);
          expect(
            pages.toList()..sort(),
            List.generate(spec.length, (i) => i),
            reason: '$spec shift=$shift',
          );
        }
      }
    });
  });

  group('spreadIndexForPage', () {
    test('finds correct spread for each page', () {
      final spreads = computeSpreads(_pages('ppppp'), isRtl: true);
      expect(spreadIndexForPage(spreads, 0), 0);
      expect(spreadIndexForPage(spreads, 1), 1);
      expect(spreadIndexForPage(spreads, 2), 1);
      expect(spreadIndexForPage(spreads, 3), 2);
      expect(spreadIndexForPage(spreads, 4), 2);
    });

    test('returns 0 for invalid page index', () {
      final spreads = computeSpreads(_pages('ppp'), isRtl: true);
      expect(spreadIndexForPage(spreads, 99), 0);
    });
  });

  group('readProgressFor', () {
    test('counts the furthest page on screen', () {
      // A 200-page book whose last spread shows pages 198 and 199.
      expect(readProgressFor([199, 198], 200), 1.0);
      expect(readProgressFor([0], 200), 0.0);
      expect(readProgressFor([99], 199), 0.5);
    });

    test('a one-page book has no progress to make', () {
      expect(readProgressFor([0], 1), 0.0);
    });
  });

  group('PageSpread', () {
    test(
      'primaryPageIndex returns lower-numbered page for two-page spread',
      () {
        const spread = PageSpread(leftPageIndex: 4, rightPageIndex: 3);
        expect(spread.primaryPageIndex, 3);
      },
    );

    test('primaryPageIndex returns the solo page index', () {
      const spread = PageSpread(rightPageIndex: 5);
      expect(spread.primaryPageIndex, 5);
    });

    test('containsPage works for both sides', () {
      const spread = PageSpread(leftPageIndex: 2, rightPageIndex: 1);
      expect(spread.containsPage(1), isTrue);
      expect(spread.containsPage(2), isTrue);
      expect(spread.containsPage(3), isFalse);
    });

    test('equality and hashCode', () {
      const a = PageSpread(leftPageIndex: 2, rightPageIndex: 1);
      const b = PageSpread(leftPageIndex: 2, rightPageIndex: 1);
      const c = PageSpread(leftPageIndex: 1, rightPageIndex: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
