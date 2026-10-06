import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_scroll_view.dart';

MokuroPage _page(int index, int width, int height) => MokuroPage(
  pageIndex: index,
  imageFileName: '$index.png',
  imgWidth: width,
  imgHeight: height,
  blocks: const [],
);

void main() {
  group('mangaScrollPageTops', () {
    test('stacks pages at full width and their own shape', () {
      final tops = mangaScrollPageTops([
        _page(0, 700, 1000),
        _page(1, 1000, 500),
        _page(2, 0, 0), // unreadable size: the scroll view's 0.7 fallback
      ], 350);

      expect(tops, [
        for (final top in [0, 500, 675, 1175]) closeTo(top, 1e-9),
      ]);
    });
  });

  group('mangaScrollPageAt', () {
    // Pages 600 tall in a 1000 tall viewport: about 1.7 pages per screen.
    final tops = mangaScrollPageTops([
      for (var i = 0; i < 10; i++) _page(i, 500, 600),
    ], 500);

    int pageAt(double offset) =>
        mangaScrollPageAt(tops, offset: offset, viewport: 1000);

    test('is the page at the middle of the screen', () {
      expect(pageAt(0), 0); // middle at 500, inside page 0 (0-600)
      expect(pageAt(200), 1); // middle at 700
      expect(pageAt(2500), 5); // middle at 3000, the start of page 5
    });

    test('is the last page once the view cannot scroll further', () {
      // A 1400 viewport at its furthest (6000 - 1400): the middle, at 5300,
      // is still on page 8, but the whole of page 9 is on screen.
      expect(mangaScrollPageAt(tops, offset: 4600, viewport: 1400), 9);
      expect(mangaScrollPageAt(tops, offset: 4500, viewport: 1400), 8);
    });

    test('a book shorter than the screen is all on its last page', () {
      final short = mangaScrollPageTops([_page(0, 500, 300)], 500);
      expect(mangaScrollPageAt(short, offset: 0, viewport: 1000), 0);
    });
  });
}
