// Paginated reader on a real WebView: swiping down shows the controls,
// swiping up hides them, a tap in the top or bottom page margin shows them,
// and none of it moves the page. (Android used to see each vertical swipe
// as a tap; see disableVerticalScroll in custom_epub_viewer.dart.)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '縦スワイプテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_gestures_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('swipes and margin taps toggle the controls, moving nothing', (
    tester,
  ) async {
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    final viewer = find.byType(CustomEpubViewer);
    final controls = find.byIcon(Icons.bookmarks_outlined);
    const waitFor = Duration(seconds: 5);

    // Every scroll offset a gesture could move, plus the page.
    Future<Object?> position() => controller.debugEvaluateJavascript(
      '(function () {'
      '  var c = rendition.manager.container;'
      '  var d = rendition.getContents()[0].document.scrollingElement;'
      '  var v = document.getElementById("viewer");'
      '  return JSON.stringify([window.scrollX, window.scrollY,'
      '    v.scrollLeft, v.scrollTop, c.scrollLeft, c.scrollTop,'
      '    d.scrollLeft, d.scrollTop,'
      '    rendition.location.start.cfi]);'
      '})()',
    );

    // Gestures stay near the left edge, outside the center zone where a tap
    // would toggle the controls anyway, and where a tap turns the page.
    Future<void> swipe(double fromY, double toY) {
      final rect = tester.getRect(viewer);
      return tester.timedDragFrom(
        rect.topLeft + Offset(rect.width * 0.15, rect.height * fromY),
        Offset(0, rect.height * (toY - fromY)),
        const Duration(milliseconds: 300),
      );
    }

    // The margins are 28px by default.
    Future<void> tapMargin({required bool top}) {
      final rect = tester.getRect(viewer);
      return tester.tapAt(
        Offset(
          rect.left + rect.width * 0.15,
          top ? rect.top + 12 : rect.bottom - 12,
        ),
      );
    }

    final before = await position();
    expect(controls, findsNothing);

    await swipe(0.25, 0.7);
    await pumpUntilVisible(tester, controls, timeout: waitFor);
    expect(await position(), before);

    await swipe(0.7, 0.25);
    await pumpUntilGone(tester, controls, timeout: waitFor);
    expect(await position(), before);

    await tapMargin(top: true);
    await pumpUntilVisible(tester, controls, timeout: waitFor);
    await swipe(0.7, 0.25);
    await pumpUntilGone(tester, controls, timeout: waitFor);

    await tapMargin(top: false);
    await pumpUntilVisible(tester, controls, timeout: waitFor);
    expect(await position(), before);
  });
}
