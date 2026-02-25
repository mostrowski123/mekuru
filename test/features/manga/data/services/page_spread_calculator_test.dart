import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';

void main() {
  group('computeSpreads', () {
    test('returns empty list for 0 pages', () {
      expect(computeSpreads(0, isRtl: true), isEmpty);
      expect(computeSpreads(0, isRtl: false), isEmpty);
    });

    test('1 page (cover only) returns single spread', () {
      final rtl = computeSpreads(1, isRtl: true);
      expect(rtl, hasLength(1));
      expect(rtl[0].isSinglePage, isTrue);
      expect(rtl[0].rightPageIndex, 0);
      expect(rtl[0].leftPageIndex, isNull);

      final ltr = computeSpreads(1, isRtl: false);
      expect(ltr, hasLength(1));
      expect(ltr[0].isSinglePage, isTrue);
      expect(ltr[0].leftPageIndex, 0);
      expect(ltr[0].rightPageIndex, isNull);
    });

    test('2 pages: cover solo + page 1 solo', () {
      final rtl = computeSpreads(2, isRtl: true);
      expect(rtl, hasLength(2));
      // Cover
      expect(rtl[0], const PageSpread(rightPageIndex: 0));
      // Page 1 solo
      expect(rtl[1], const PageSpread(rightPageIndex: 1));
    });

    test('3 pages: cover solo + two-page spread (1,2)', () {
      final rtl = computeSpreads(3, isRtl: true);
      expect(rtl, hasLength(2));
      expect(rtl[0], const PageSpread(rightPageIndex: 0));
      // RTL: left=higher, right=lower
      expect(rtl[1], const PageSpread(leftPageIndex: 2, rightPageIndex: 1));

      final ltr = computeSpreads(3, isRtl: false);
      expect(ltr, hasLength(2));
      expect(ltr[0], const PageSpread(leftPageIndex: 0));
      // LTR: left=lower, right=higher
      expect(ltr[1], const PageSpread(leftPageIndex: 1, rightPageIndex: 2));
    });

    test('4 pages: cover + spread(1,2) + trailing page 3 solo', () {
      final rtl = computeSpreads(4, isRtl: true);
      expect(rtl, hasLength(3));
      expect(rtl[0], const PageSpread(rightPageIndex: 0));
      expect(rtl[1], const PageSpread(leftPageIndex: 2, rightPageIndex: 1));
      expect(rtl[2], const PageSpread(rightPageIndex: 3));
    });

    test('5 pages: cover + spread(1,2) + spread(3,4)', () {
      final rtl = computeSpreads(5, isRtl: true);
      expect(rtl, hasLength(3));
      expect(rtl[0], const PageSpread(rightPageIndex: 0));
      expect(rtl[1], const PageSpread(leftPageIndex: 2, rightPageIndex: 1));
      expect(rtl[2], const PageSpread(leftPageIndex: 4, rightPageIndex: 3));
    });

    test('RTL vs LTR page ordering within spreads', () {
      final rtl = computeSpreads(5, isRtl: true);
      // RTL spread: left=higher index, right=lower index
      expect(rtl[1].leftPageIndex, 2);
      expect(rtl[1].rightPageIndex, 1);

      final ltr = computeSpreads(5, isRtl: false);
      // LTR spread: left=lower index, right=higher index
      expect(ltr[1].leftPageIndex, 1);
      expect(ltr[1].rightPageIndex, 2);
    });

    test('all pages are accounted for', () {
      for (final count in [1, 2, 3, 5, 10, 21, 100]) {
        final spreads = computeSpreads(count, isRtl: true);
        final allPages = <int>{};
        for (final s in spreads) {
          if (s.leftPageIndex != null) allPages.add(s.leftPageIndex!);
          if (s.rightPageIndex != null) allPages.add(s.rightPageIndex!);
        }
        expect(allPages, equals(Set.from(List.generate(count, (i) => i))),
            reason: 'All pages should be present for count=$count');
      }
    });
  });

  group('spreadIndexForPage', () {
    test('finds correct spread for each page', () {
      final spreads = computeSpreads(5, isRtl: true);
      expect(spreadIndexForPage(spreads, 0), 0);
      expect(spreadIndexForPage(spreads, 1), 1);
      expect(spreadIndexForPage(spreads, 2), 1);
      expect(spreadIndexForPage(spreads, 3), 2);
      expect(spreadIndexForPage(spreads, 4), 2);
    });

    test('returns 0 for invalid page index', () {
      final spreads = computeSpreads(3, isRtl: true);
      expect(spreadIndexForPage(spreads, 99), 0);
    });
  });

  group('PageSpread', () {
    test('primaryPageIndex returns lower-numbered page for two-page spread', () {
      const spread = PageSpread(leftPageIndex: 4, rightPageIndex: 3);
      expect(spread.primaryPageIndex, 3);
    });

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
