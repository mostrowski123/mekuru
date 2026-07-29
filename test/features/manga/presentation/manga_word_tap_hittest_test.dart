import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';

/// Reproduces the manga reader's tap routing: an outer GestureDetector
/// (menu toggle / page turn zones) wrapping a PageView of MangaPageView,
/// whose word overlay carries per-word tap targets.
///
/// Regression scenario: tapping directly on a word near the top of the
/// screen must reach the word overlay, not fall through to the outer
/// detector (which would toggle the controls overlay).
void main() {
  // Logical viewport 360x800 (phone portrait).
  const physicalSize = Size(1080, 2400);
  const dpr = 3.0;

  // Image 1000x2000 -> contain scale = min(360/1000, 800/2000) = 0.36
  // renderedH = 720, offsetY = (800-720)/2 = 40, offsetX = 0.
  const scale = 0.36;
  const offsetY = 40.0;

  const topWordBox = Rect.fromLTRB(480, 30, 560, 190);
  const midWordBox = Rect.fromLTRB(480, 950, 560, 1110);

  Offset screenCenterOf(Rect imageRect) => Offset(
    (imageRect.left + imageRect.right) / 2 * scale,
    (imageRect.top + imageRect.bottom) / 2 * scale + offsetY,
  );

  MokuroPage buildPage() {
    const topWord = MokuroWord(
      surface: 'トップ',
      boundingBox: topWordBox,
      blockIndex: 0,
      lineIndex: 0,
      charStartInLine: 0,
      charEndInLine: 3,
    );
    const midWord = MokuroWord(
      surface: 'まんなか',
      boundingBox: midWordBox,
      blockIndex: 0,
      lineIndex: 1,
      charStartInLine: 0,
      charEndInLine: 4,
    );
    const block = MokuroTextBlock(
      box: [480, 30, 560, 1110],
      vertical: true,
      fontSize: 40,
      linesCoords: [],
      lines: ['トップ', 'まんなか'],
      words: [topWord, midWord],
    );
    return const MokuroPage(
      pageIndex: 0,
      imageFileName: 'p1.jpg',
      imgWidth: 1000,
      imgHeight: 2000,
      blocks: [block],
    );
  }

  Future<({List<String> words, List<int> pages, List<Offset> fallback})>
  pumpReader(WidgetTester tester, {int pageIndex = 0}) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    final words = <String>[];
    final pages = <int>[];
    final fallback = <Offset>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              GestureDetector(
                onTapUp: (d) => fallback.add(d.globalPosition),
                child: PageView.builder(
                  itemCount: 1,
                  itemBuilder: (_, _) => MangaPageView(
                    pageIndex: pageIndex,
                    page: buildPage(),
                    imageDirPath: 'Z:/does-not-exist',
                    onWordTapped: (p, w, _, _) {
                      pages.add(p);
                      words.add(w.surface);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Let the (missing) image resolve to its errorBuilder.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    return (words: words, pages: pages, fallback: fallback);
  }

  testWidgets('tap directly on a word near the top hits the word overlay', (
    tester,
  ) async {
    final taps = await pumpReader(tester);

    await tester.tapAt(screenCenterOf(topWordBox));
    await tester.pump();

    expect(taps.words, ['トップ']);
    expect(taps.fallback, isEmpty);
  });

  testWidgets('tap on a mid-screen word hits the word overlay', (tester) async {
    final taps = await pumpReader(tester);

    await tester.tapAt(screenCenterOf(midWordBox));
    await tester.pump();

    expect(taps.words, ['まんなか']);
    expect(taps.fallback, isEmpty);
  });

  testWidgets('tap on empty page area falls through to the outer detector', (
    tester,
  ) async {
    final taps = await pumpReader(tester);

    await tester.tapAt(const Offset(300, 600));
    await tester.pump();

    expect(taps.words, isEmpty);
    expect(taps.fallback, hasLength(1));
  });

  testWidgets('word tap reports the page index it was constructed with', (
    tester,
  ) async {
    final taps = await pumpReader(tester, pageIndex: 3);

    await tester.tapAt(screenCenterOf(topWordBox));
    await tester.pump();

    expect(taps.pages, [3]);
  });
}
