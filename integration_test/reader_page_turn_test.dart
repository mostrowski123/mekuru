// Page turn animation in the EPUB reader, on a real WebView: every turn
// moves exactly one page and the picture of the old page never stays up.
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '頁めくりテスト';
const _picture = Key('page-turn-picture');

/// Where the reader is: spine index, page within it and that section's
/// page count.
Future<(int, int, int)> _place(CustomEpubController controller) async {
  final at = await evalJson(
    controller,
    '(function () {'
    '  var s = rendition.currentLocation().start;'
    '  return JSON.stringify({index: s.index, page: s.displayed.page,'
    '    total: s.displayed.total});'
    '})()',
  );
  return (at['index'] as int, at['page'] as int, at['total'] as int);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_page_turn_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a curl turns one page at a time and never stays up', (
    tester,
  ) async {
    // Test emulators run with system animations off, and that turns page
    // turns off too.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(pageTurnStyle: PageTurnStyle.curl),
    );

    /// Presses a page key and waits for the turn to finish. Returns
    /// whether the picture of the old page was seen on the way.
    Future<bool> turn({required bool forward}) async {
      await tester.sendKeyEvent(
        forward ? LogicalKeyboardKey.pageDown : LogicalKeyboardKey.pageUp,
      );
      var seen = false;
      // Capture, the wait for the new page (at most 700 ms) and the curl.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final up = find.byKey(_picture).evaluate().isNotEmpty;
        seen = seen || up;
        if (seen && !up) break;
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(_picture), findsNothing);
      return seen;
    }

    final start = await _place(controller);
    expect((start.$1, start.$2), (0, 1));
    expect(start.$3, greaterThan(5), reason: 'the chapter needs six pages');

    // Inside a chapter.
    expect(await turn(forward: true), isTrue, reason: 'no animation played');
    expect(await _place(controller), (0, 2, start.$3));

    // Two turns asked for at once still move two pages. (Inside a chapter:
    // at its last page both would ask for the next chapter.)
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await turn(forward: true);
    await tester.pump(const Duration(seconds: 1));
    expect(await _place(controller), (0, 4, start.$3));

    // A finger dragged across the page takes the page with it. Android
    // only: a test's touches do not reach WKWebView.
    var page = 4;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final viewer = tester.getRect(find.byType(CustomEpubViewer));
      Future<TestGesture> dragRight(double from, double by) async {
        final finger = await tester.startGesture(
          Offset(viewer.left + viewer.width * from, viewer.center.dy),
        );
        for (var i = 0; i < 6; i++) {
          await finger.moveBy(Offset(viewer.width * by / 6, 0));
          await tester.pump(const Duration(milliseconds: 40));
        }
        return finger;
      }

      // Vertical text reads right to left: rightwards is forwards.
      final finger = await dragRight(0.3, 0.3);
      await pumpUntilVisible(tester, find.byKey(_picture));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(_picture),
        findsOneWidget,
        reason: 'the page waits under the finger',
      );
      expect(await _place(controller), (
        0,
        5,
        start.$3,
      ), reason: 'the next page is underneath');
      await finger.up();
      await pumpUntilGone(tester, find.byKey(_picture));
      expect(await _place(controller), (0, 5, start.$3));
      page = 5;

      // Dragged out and back again, the page stays where it was.
      final back = await dragRight(0.3, 0.3);
      await pumpUntilVisible(tester, find.byKey(_picture));
      for (var i = 0; i < 6; i++) {
        await back.moveBy(Offset(-viewer.width * 0.28 / 6, 0));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await back.up();
      await pumpUntilGone(tester, find.byKey(_picture));
      await tester.pump(const Duration(milliseconds: 500));
      expect(await _place(controller), (0, 5, start.$3));
    }

    // On to the next chapter, one page at a time.
    for (page++; page <= start.$3; page++) {
      await turn(forward: true);
      expect((await _place(controller)).$2, page);
    }
    expect(await turn(forward: true), isTrue);
    final second = await _place(controller);
    expect((second.$1, second.$2), (1, 1));

    // Back into the chapter before: its last page, not its first.
    expect(await turn(forward: false), isTrue);
    expect(await _place(controller), (0, start.$3, start.$3));

    // At the very end of the book a turn changes nothing and leaves no
    // picture behind.
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.last().href); true',
    );
    await tester.pump(const Duration(seconds: 2));
    var end = await _place(controller);
    for (var page = end.$2; page < end.$3; page++) {
      await turn(forward: true);
    }
    end = await _place(controller);
    expect(end.$2, end.$3);
    await turn(forward: true);
    expect(await _place(controller), end);
    expect(tester.takeException(), isNull);
  });
}
