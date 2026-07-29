import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_highlight_overlay.dart';

void main() {
  testWidgets('maps image-space rects to screen space with scale and offset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MangaWordHighlightOverlay(
          rects: [
            Rect.fromLTRB(0, 0, 100, 50),
            Rect.fromLTRB(200, 100, 300, 200),
          ],
          scale: 0.5,
          offsetX: 10,
          offsetY: 20,
        ),
      ),
    );

    final boxes = find.descendant(
      of: find.byType(MangaWordHighlightOverlay),
      matching: find.byType(Container),
    );
    expect(boxes, findsNWidgets(2));
    expect(tester.getRect(boxes.at(0)), const Rect.fromLTRB(10, 20, 60, 45));
    expect(tester.getRect(boxes.at(1)), const Rect.fromLTRB(110, 70, 160, 120));
  });

  testWidgets('drops degenerate rects instead of rendering them', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MangaWordHighlightOverlay(
          rects: [Rect.fromLTRB(5, 5, 5, 5), Rect.fromLTRB(0, 0, 100, 50)],
          scale: 1,
          offsetX: 0,
          offsetY: 0,
        ),
      ),
    );

    final boxes = find.descendant(
      of: find.byType(MangaWordHighlightOverlay),
      matching: find.byType(Container),
    );
    expect(boxes, findsOneWidget);
    expect(tester.getRect(boxes), const Rect.fromLTRB(0, 0, 100, 50));
  });
}
