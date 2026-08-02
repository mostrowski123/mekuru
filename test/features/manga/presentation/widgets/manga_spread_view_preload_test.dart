import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';

import '../../../../shared/saf_image_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> readPaths;

  setUp(() => readPaths = stubSafImageReads());
  tearDown(clearSafImageStub);

  testWidgets('adjacent spread images start loading while the current '
      'spread is on screen', (tester) async {
    final pages = List.generate(
      5,
      (i) => MokuroPage(
        pageIndex: i,
        imageFileName: 'p$i.png',
        imgWidth: 100,
        imgHeight: 150,
        blocks: const [],
      ),
    );
    final book = MokuroBook(
      title: 'test',
      imageDirPath: '/unused',
      safTreeUri: 'content://tree/test',
      safImageDirRelativePath: 'imgs',
      pages: pages,
    );
    // RTL: spreads are [0], [2,1], [4,3].
    final spreads = computeSpreads(pages.length, isRtl: true);

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
}
