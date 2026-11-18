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
    final shown = Completer<void>();
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

    shown.complete();
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
            pageShown: Completer<void>().future,
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
            pageShown: Completer<void>().future,
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
}
