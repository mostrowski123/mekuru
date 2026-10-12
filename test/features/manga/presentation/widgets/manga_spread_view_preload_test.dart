import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';

import '../../../../shared/saf_image_fixtures.dart';

/// A book of [pageCount] portrait pages read through SAF.
MokuroBook _book(int pageCount) => MokuroBook(
  title: 'test',
  imageDirPath: '/unused',
  safTreeUri: 'content://tree/test',
  safImageDirRelativePath: 'imgs',
  pages: List.generate(
    pageCount,
    (i) => MokuroPage(
      pageIndex: i,
      imageFileName: 'p$i.png',
      imgWidth: 100,
      imgHeight: 150,
      blocks: const [],
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> readPaths;

  setUp(() => readPaths = stubSafImageReads());
  tearDown(clearSafImageStub);

  testWidgets('adjacent spread images start loading while the current '
      'spread is on screen', (tester) async {
    final book = _book(5);
    // RTL: spreads are [0], [2,1], [4,3].
    final spreads = computeSpreads(book.pages, isRtl: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MangaSpreadView(
          mokuroBook: book,
          spreads: spreads,
          isRtl: true,
          animatePageTurns: false,
        ),
      ),
    );

    // Pages of the next spread must be requested ahead of time so an
    // instant (no-animation) page turn has pixels ready to show.
    await pumpUntil(
      tester,
      () =>
          readPaths.contains('imgs/p1.png') &&
          readPaths.contains('imgs/p2.png'),
      description: 'the next spread to preload while spread 0 is shown',
    );
    expect(readPaths, contains('imgs/p0.png'));
  });

  testWidgets('new pairs keep the page on screen', (tester) async {
    final book = _book(7);
    Widget view(List<PageSpread> spreads, int initial) => MaterialApp(
      home: MangaSpreadView(
        mokuroBook: book,
        spreads: spreads,
        initialSpreadIndex: initial,
        animatePageTurns: false,
      ),
    );
    double? shownSpread() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page;

    // [0], [1,2], [3,4], [5,6]: page 3 is in spread 2.
    final unshifted = computeSpreads(book.pages, isRtl: true);
    await tester.pumpWidget(view(unshifted, 2));
    await tester.pump();
    expect(shownSpread(), 2);

    // [0,1], [2,3], [4,5], [6]: page 3 is now in spread 1, which the
    // reader passes along with the new pairs.
    final shifted = computeSpreads(book.pages, isRtl: true, shift: true);
    await tester.pumpWidget(view(shifted, spreadIndexForPage(shifted, 3)));
    await tester.pump();
    expect(shownSpread(), 1);
  });
}
