import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_zoom_viewer.dart';

// The default test surface is 800x600; pages start on index 1 of 5.
const _center = Offset(400, 300);

Future<PageController> _pumpPages(
  WidgetTester tester, {
  bool animatePageTurns = true,
  bool reverse = false,
}) async {
  final controller = PageController(initialPage: 1);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      // Stands in for the reader's tap zones, which hold the gesture arena
      // until a touch moves past the touch slop.
      home: GestureDetector(
        onTapUp: (_) {},
        child: PageView.builder(
          controller: controller,
          reverse: reverse,
          allowImplicitScrolling: true,
          physics: const NeverScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          itemCount: 5,
          itemBuilder: (_, index) => MangaZoomViewer(
            pageIndex: index,
            pageController: controller,
            animatePageTurns: animatePageTurns,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    ),
  );
  return controller;
}

double _scaleOf(WidgetTester tester, int pageIndex) {
  final viewer = find.byWidgetPredicate(
    (w) => w is MangaZoomViewer && w.pageIndex == pageIndex,
    // Pages kept for implicit scrolling are offstage.
    skipOffstage: false,
  );
  return tester
      .widget<InteractiveViewer>(
        find.descendant(
          of: viewer,
          matching: find.byType(InteractiveViewer, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .transformationController!
      .value
      .getMaxScaleOnAxis();
}

/// Moves each finger by its step [steps] times, pumping between moves.
Future<void> _move(
  WidgetTester tester,
  List<(TestGesture, Offset)> fingers,
  int steps,
) async {
  for (var i = 0; i < steps; i++) {
    for (final (finger, step) in fingers) {
      await finger.moveBy(step);
    }
    await tester.pump();
  }
}

/// Symmetric pinch about the centre (to about 2.3x), leaving the page
/// centred with roughly 500px of pan room on either side.
Future<void> _zoomIn(WidgetTester tester) async {
  final a = await tester.startGesture(_center - const Offset(50, 0));
  final b = await tester.startGesture(_center + const Offset(50, 0));
  await _move(tester, [
    (a, const Offset(-10, 0)),
    (b, const Offset(10, 0)),
  ], 10);
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}

Future<void> _drag(WidgetTester tester, Offset step, int steps) async {
  final finger = await tester.startGesture(const Offset(100, 300));
  await _move(tester, [(finger, step)], steps);
  await finger.up();
}

void main() {
  testWidgets('a pinch with one finger moving sideways zooms, never turns', (
    tester,
  ) async {
    final controller = await _pumpPages(tester);

    // Fingers far apart: the first 20px step passes the touch slop before
    // the span has changed by 5%, which is where a PageView drag used to
    // win the gesture arena.
    final still = await tester.startGesture(const Offset(100, 300));
    final moving = await tester.startGesture(const Offset(700, 300));
    await _move(tester, [(moving, const Offset(20, 0))], 15);
    await still.up();
    await moving.up();
    await tester.pumpAndSettle();

    expect(controller.page, 1);
    expect(_scaleOf(tester, 1), greaterThan(1.4));
  });

  testWidgets('an unzoomed swipe drags the page and turns it', (tester) async {
    final controller = await _pumpPages(tester);

    await _drag(tester, const Offset(-25, 0), 20);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
  });

  testWidgets('a short flick turns the page', (tester) async {
    final controller = await _pumpPages(tester);

    // The tap zones hold the gesture until the 18px touch slop, so the
    // viewer hears about only the last few pixels of this flick.
    await tester.flingFrom(_center, const Offset(-24, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
  });

  testWidgets('right-to-left: a flick to the right turns forward', (
    tester,
  ) async {
    final controller = await _pumpPages(tester, reverse: true);

    await tester.flingFrom(_center, const Offset(60, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
  });

  testWidgets('a second swipe while the page still settles turns again', (
    tester,
  ) async {
    final controller = await _pumpPages(tester);

    await _drag(tester, const Offset(-25, 0), 20);
    // Mid-settle: the first pump only starts the settle animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.page, isNot(2));
    await _drag(tester, const Offset(-25, 0), 36);
    await tester.pumpAndSettle();

    expect(controller.page, 3);
  });

  testWidgets('a zoomed pan away from the edge pans, not turns', (
    tester,
  ) async {
    final controller = await _pumpPages(tester);
    await _zoomIn(tester);

    final scale = _scaleOf(tester, 1);
    await _drag(tester, const Offset(25, 0), 10);
    await tester.pumpAndSettle();

    expect(controller.page, 1);
    expect(_scaleOf(tester, 1), scale);
  });

  testWidgets('dragging past a zoomed page\'s edge turns it, then resets it', (
    tester,
  ) async {
    final controller = await _pumpPages(tester);
    await _zoomIn(tester);

    // 800px pans to the left edge; the remaining 600px drags the page.
    await _drag(tester, const Offset(25, 0), 56);
    await tester.pumpAndSettle();

    expect(controller.page, 0);
    expect(_scaleOf(tester, 1), 1);
  });

  testWidgets('e-reader mode jumps on release past a zoomed page\'s edge', (
    tester,
  ) async {
    final controller = await _pumpPages(tester, animatePageTurns: false);
    await _zoomIn(tester);

    await _drag(tester, const Offset(25, 0), 40);
    await tester.pump();

    expect(controller.page, 0);
  });

  testWidgets('e-reader mode leaves unzoomed swipes to the screen', (
    tester,
  ) async {
    final controller = await _pumpPages(tester, animatePageTurns: false);

    await _drag(tester, const Offset(-25, 0), 20);
    await tester.pumpAndSettle();

    expect(controller.page, 1);
  });
}
