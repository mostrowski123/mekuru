import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/page_turn_overlay.dart';

const _picture = Key('page-turn-picture');

Future<ui.Image> _image(WidgetTester tester) async => (await tester.runAsync(
  () => createTestImage(width: 4, height: 4, cache: false),
))!;

Future<PageTurnController> _pumpOverlay(WidgetTester tester) async {
  final controller = PageTurnController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PageTurnOverlay(
        controller: controller,
        child: const SizedBox.expand(),
      ),
    ),
  );
  return controller;
}

/// Lets a running animation of [length] finish and the overlay rebuild.
Future<void> _pumpThrough(WidgetTester tester, Duration length) async {
  await tester.pump();
  await tester.pump(length);
  await tester.pump();
}

void main() {
  testWidgets('covers the page, turns it once, plays and clears', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var turns = 0, done = false;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.slide,
            leavesRight: true,
            capture: () async => image,
            turnPage: () => turns++,
          )
          .then((_) => done = true),
    );
    // The page must not change before the picture covers it.
    expect(turns, 0);

    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    expect(turns, 1);

    await _pumpThrough(tester, const Duration(milliseconds: 300));
    expect(find.byKey(_picture), findsNothing);
    expect(turns, 1);
    expect(done, isTrue);
  });

  testWidgets('waits for the new page before it plays', (tester) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    final shown = Completer<bool>();
    unawaited(
      controller.run(
        style: PageTurnStyle.slide,
        leavesRight: false,
        capture: () async => image,
        turnPage: () {},
        pageShown: shown.future,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_picture), findsOneWidget, reason: 'still waiting');

    shown.complete(true);
    await tester.pump(); // the turn hears that the page is there
    await _pumpThrough(tester, const Duration(milliseconds: 300));
    expect(find.byKey(_picture), findsNothing);
  });

  testWidgets('drops the picture when the new page never arrives', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var turns = 0, done = false;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.curl,
            leavesRight: true,
            capture: () async => image,
            turnPage: () => turns++,
            pageShown: Completer<bool>().future,
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 699));
    expect(find.byKey(_picture), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(turns, 1);
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a turn asked for while one plays ends it and is not animated', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var first = 0, second = 0, firstDone = false, captures = 0;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.curl,
            leavesRight: true,
            capture: () async => image,
            turnPage: () => first++,
          )
          .then((_) => firstDone = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_picture), findsOneWidget);

    unawaited(
      controller.run(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async {
          captures++;
          return null;
        },
        turnPage: () => second++,
      ),
    );
    expect([first, second], [1, 1]);
    await tester.pump();
    expect(firstDone, isTrue);
    expect(captures, 0);
    expect(find.byKey(_picture), findsNothing);
  });

  testWidgets('turns asked for while the picture is taken each turn once', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    final captured = Completer<ui.Image?>();
    var first = 0, second = 0;
    unawaited(
      controller.run(
        style: PageTurnStyle.slide,
        leavesRight: true,
        capture: () => captured.future,
        turnPage: () => first++,
      ),
    );
    unawaited(
      controller.run(
        style: PageTurnStyle.slide,
        leavesRight: true,
        capture: () async => fail('a second picture was taken'),
        turnPage: () => second++,
      ),
    );
    expect([first, second], [0, 1]);

    captured.complete(image);
    await tester.pump();
    await tester.pump();
    expect([first, second], [1, 1]);
    expect(find.byKey(_picture), findsNothing);
  });

  testWidgets('with no picture the page just turns', (tester) async {
    final controller = await _pumpOverlay(tester);
    var turns = 0;
    await controller.run(
      style: PageTurnStyle.curl,
      leavesRight: true,
      capture: () async => null,
      turnPage: () => turns++,
    );
    await controller.run(
      style: PageTurnStyle.curl,
      leavesRight: true,
      capture: () => throw StateError('the web view is gone'),
      turnPage: () => turns++,
    );
    expect(turns, 2);
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the reader mid-turn turns the page and cleans up', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var turns = 0, done = false;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.slide,
            leavesRight: true,
            capture: () async => image,
            turnPage: () => turns++,
            pageShown: Completer<bool>().future,
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(turns, 1);
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a curl shader that cannot load does not break the turn', (
    tester,
  ) async {
    final load = PageTurnOverlay.debugLoadCurl;
    addTearDown(() => PageTurnOverlay.debugLoadCurl = load);
    PageTurnOverlay.debugLoadCurl = () => Future.error(Exception('no shader'));

    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var done = false;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.curl,
            leavesRight: true,
            capture: () async => image,
            turnPage: () {},
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump();
    await _pumpThrough(tester, const Duration(milliseconds: 500));
    expect(done, isTrue);
    expect(find.byKey(_picture), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no animation, or no overlay, the page just turns', (
    tester,
  ) async {
    final attached = await _pumpOverlay(tester);
    var turns = 0;
    Future<ui.Image?> noPicture() async => fail('a picture was taken');
    unawaited(
      attached.run(
        style: PageTurnStyle.none,
        leavesRight: true,
        capture: noPicture,
        turnPage: () => turns++,
      ),
    );
    expect(turns, 1);

    unawaited(
      PageTurnController().run(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: noPicture,
        turnPage: () => turns++,
      ),
    );
    expect(turns, 2);
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
  });

  testWidgets('drops the picture at once when there is no page to turn to', (
    tester,
  ) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    final shown = Completer<bool>();
    var done = false;
    unawaited(
      controller
          .run(
            style: PageTurnStyle.curl,
            leavesRight: true,
            capture: () async => image,
            turnPage: () {},
            pageShown: shown.future,
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);

    shown.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(done, isTrue);
  });

  testWidgets('a picture that never comes is given up on', (tester) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var turns = 0;
    unawaited(
      controller.run(
        style: PageTurnStyle.slide,
        leavesRight: true,
        capture: () => Completer<ui.Image?>().future,
        turnPage: () => turns++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(turns, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(turns, 1);
    expect(find.byKey(_picture), findsNothing);

    // The next turn is animated again.
    unawaited(
      controller.run(
        style: PageTurnStyle.slide,
        leavesRight: true,
        capture: () async => image,
        turnPage: () => turns++,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    await _pumpThrough(tester, const Duration(milliseconds: 300));
    expect(turns, 2);
  });

  testWidgets('a touch elsewhere ends the turn on screen', (tester) async {
    final controller = await _pumpOverlay(tester);
    final image = await _image(tester);
    var turns = 0;
    unawaited(
      controller.run(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => image,
        turnPage: () => turns++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_picture), findsOneWidget);

    controller.finish();
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(turns, 1);
  });

  group('a turn that follows the finger', () {
    testWidgets('moves with it and finishes when let go far enough', (
      tester,
    ) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      var turns = 0, backs = 0;
      final drag = controller.drag(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => image,
        turnPage: () => turns++,
        turnBack: () {
          backs++;
          return null;
        },
      );
      drag.update(0.1);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_picture), findsOneWidget);
      expect(turns, 1, reason: 'the next page is already underneath');

      drag.update(0.4);
      await tester.pump();
      expect(controller.debugProgress, 0.4);
      // It stays where the finger holds it.
      await tester.pump(const Duration(seconds: 2));
      expect(controller.debugProgress, 0.4);
      expect(find.byKey(_picture), findsOneWidget);

      drag.end(complete: true);
      await _pumpThrough(tester, const Duration(milliseconds: 500));
      expect(find.byKey(_picture), findsNothing);
      expect([turns, backs], [1, 0]);
    });

    testWidgets('let go early, the page goes back', (tester) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      final back = Completer<bool>();
      var turns = 0, backs = 0;
      final drag = controller.drag(
        style: PageTurnStyle.slide,
        leavesRight: false,
        capture: () async => image,
        turnPage: () => turns++,
        turnBack: () {
          backs++;
          return back.future;
        },
      );
      await tester.pump();
      await tester.pump();
      // The page leaves to the left, so a finger going right moves nothing.
      drag.update(0.2);
      await tester.pump();
      expect(controller.debugProgress, 0);
      drag.update(-0.2);
      await tester.pump();
      expect(controller.debugProgress, 0.2);

      drag.end(complete: false);
      await _pumpThrough(tester, const Duration(milliseconds: 300));
      expect([turns, backs], [1, 1]);
      expect(controller.debugProgress, 0);
      // The picture covers the reader until the old page is back.
      expect(find.byKey(_picture), findsOneWidget);

      back.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_picture), findsNothing);
      expect([turns, backs], [1, 1]);
    });

    testWidgets('given up, the page goes back even when the run back is cut '
        'short', (tester) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      var turns = 0, backs = 0;
      final drag = controller.drag(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => image,
        turnPage: () => turns++,
        turnBack: () {
          backs++;
          return null;
        },
      );
      await tester.pump();
      await tester.pump();
      drag.update(0.6);
      await tester.pump();
      drag.end(complete: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(backs, 0, reason: 'still running back');

      // Another turn, a tapped word, the reader closing.
      controller.finish();
      await tester.pump();
      expect(find.byKey(_picture), findsNothing);
      expect([turns, backs], [1, 1]);
    });

    testWidgets('waits for the new page before it moves', (tester) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      final shown = Completer<bool>();
      final drag = controller.drag(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => image,
        turnPage: () {},
        pageShown: shown.future,
        turnBack: () => null,
      );
      await tester.pump();
      await tester.pump();
      drag.update(0.5);
      await tester.pump();
      expect(controller.debugProgress, 0, reason: 'nothing to uncover yet');

      shown.complete(true);
      await tester.pump();
      await tester.pump();
      expect(controller.debugProgress, 0.5);

      drag.end(complete: true);
      await _pumpThrough(tester, const Duration(milliseconds: 500));
      expect(find.byKey(_picture), findsNothing);
    });

    testWidgets('with no page to turn to, nothing is put back', (tester) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      var backs = 0;
      final drag = controller.drag(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => image,
        turnPage: () {},
        pageShown: Future.value(false),
        turnBack: () {
          backs++;
          return null;
        },
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_picture), findsNothing);

      drag.update(0.6);
      drag.end(complete: false);
      await tester.pump();
      expect(backs, 0);
    });

    testWidgets('without an animation it turns the page when let go', (
      tester,
    ) async {
      final controller = await _pumpOverlay(tester);
      var turns = 0;
      PageTurnDrag start() => controller.drag(
        style: PageTurnStyle.none,
        leavesRight: true,
        capture: () async => fail('a picture was taken'),
        turnPage: () => turns++,
        turnBack: () => fail('nothing to put back'),
      );

      final swipe = start()..update(0.5);
      expect(turns, 0);
      swipe.end(complete: true);
      expect(turns, 1);

      start()
        ..update(0.1)
        ..end(complete: false);
      expect(turns, 1);
      await tester.pump();
      expect(find.byKey(_picture), findsNothing);
    });

    testWidgets('let go before its picture is taken, it still plays', (
      tester,
    ) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      final captured = Completer<ui.Image?>();
      var turns = 0;
      final drag = controller.drag(
        style: PageTurnStyle.slide,
        leavesRight: true,
        capture: () => captured.future,
        turnPage: () => turns++,
        turnBack: () => fail('nothing to put back'),
      );
      drag
        ..update(0.6)
        ..end(complete: true);
      expect(turns, 0);

      captured.complete(image);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_picture), findsOneWidget);
      expect(turns, 1);
      await _pumpThrough(tester, const Duration(milliseconds: 300));
      expect(find.byKey(_picture), findsNothing);
      expect(turns, 1);
    });

    testWidgets('given up before its picture is taken, nothing happens', (
      tester,
    ) async {
      final controller = await _pumpOverlay(tester);
      final image = await _image(tester);
      final captured = Completer<ui.Image?>();
      var turns = 0;
      controller.drag(
          style: PageTurnStyle.slide,
          leavesRight: true,
          capture: () => captured.future,
          turnPage: () => turns++,
          turnBack: () => fail('nothing to put back'),
        )
        ..update(0.05)
        ..end(complete: false);

      captured.complete(image);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_picture), findsNothing);
      expect(turns, 0);
    });

    testWidgets('a picture that cannot be taken still turns on release', (
      tester,
    ) async {
      final controller = await _pumpOverlay(tester);
      var turns = 0;
      final drag = controller.drag(
        style: PageTurnStyle.curl,
        leavesRight: true,
        capture: () async => null,
        turnPage: () => turns++,
        turnBack: () => fail('nothing to put back'),
      );
      await tester.pump();
      drag.update(0.7);
      expect(turns, 0);
      drag.end(complete: true);
      expect(turns, 1);
    });
  });
}
