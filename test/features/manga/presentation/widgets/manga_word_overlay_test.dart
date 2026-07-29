import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';

MokuroTextBlock _blockWithOneWord() {
  const word = MokuroWord(
    surface: 'ことば',
    boundingBox: Rect.fromLTRB(0, 0, 100, 100),
    blockIndex: 0,
    lineIndex: 0,
    charStartInLine: 0,
    charEndInLine: 3,
  );
  return const MokuroTextBlock(
    box: [0, 0, 100, 100],
    vertical: true,
    fontSize: 24,
    linesCoords: [],
    lines: ['ことば'],
    words: [word],
  );
}

void main() {
  testWidgets('each overlay reports its own page index on word tap', (
    tester,
  ) async {
    final tappedPages = <int>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final pageIndex in const [4, 5])
              SizedBox(
                width: 200,
                height: 200,
                child: MangaWordOverlay(
                  pageIndex: pageIndex,
                  blocks: [_blockWithOneWord()],
                  scale: 1,
                  offsetX: 0,
                  offsetY: 0,
                  onWordTapped: (p, _, _, _) => tappedPages.add(p),
                ),
              ),
          ],
        ),
      ),
    );

    // Word box is [0,0,100,100] within each 200x200 overlay.
    await tester.tapAt(const Offset(50, 50)); // left overlay (page 4)
    await tester.tapAt(const Offset(250, 50)); // right overlay (page 5)

    expect(tappedPages, [4, 5]);
  });
}
