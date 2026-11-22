// Going back a chapter jumps to the chapter's last page. With the screen
// sideways a vertical page is shorter than it is wide, and once the chapter
// had settled the jump stepped by the width instead of the page height: it
// stopped part-way down a page, short of the last one. The same screen
// showed a page counter that rounded up, so that turning forward skipped a
// chapter's last page. One reader per file: see
// integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '横向きテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_landscape_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('the last page of a vertical chapter is found sideways', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await tester.pump(const Duration(seconds: 2));

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    // Settled: epub.js has put its page step back to the column width.
    await tester.pump(const Duration(seconds: 2));

    // No other navigation runs here, so the snap always goes ahead.
    await controller.debugEvaluateJavascript(
      "snapToLastPage('test', function () { return true; }); true",
    );
    await tester.pump(const Duration(seconds: 1));

    final at = await evalJson(
      controller,
      '(function () {'
      '  var c = rendition.manager.container;'
      '  return JSON.stringify({top: Math.round(c.scrollTop),'
      '    end: c.scrollHeight - c.offsetHeight,'
      '    pages: c.scrollHeight / c.offsetHeight,'
      '    wide: c.offsetWidth > c.offsetHeight});'
      '})()',
    );
    expect(at['wide'], isTrue, reason: 'needs a page wider than it is tall');
    expect(at['pages'], greaterThan(2), reason: 'needs a few pages: $at');
    expect(at['top'], at['end'], reason: '$at');

    // Turning forward shows every page of a chapter. The page counter ran
    // one ahead whenever a scroll position landed a fraction of a pixel past
    // a page boundary, and the chapter's last page was skipped. (At this
    // font size the emulators' sideways screen does that.)
    await controller.debugEvaluateJavascript('setFontSize(20); true');
    await tester.pump(const Duration(seconds: 2));
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.get(0).href); true',
    );
    await tester.pump(const Duration(seconds: 2));
    final shown = <int>[];
    var pages = 0;
    for (var turn = 0; turn < 60; turn++) {
      final here = await evalJson(
        controller,
        '(function () {'
        '  var c = rendition.manager.container;'
        '  return JSON.stringify({'
        '    index: rendition.currentLocation().start.index,'
        '    page: Math.round(c.scrollTop / c.offsetHeight) + 1,'
        '    pages: Math.round(c.scrollHeight / c.offsetHeight)});'
        '})()',
      );
      if (here['index'] != 0) break;
      shown.add(here['page'] as int);
      pages = here['pages'] as int;
      controller.next();
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(shown, [for (var page = 1; page <= pages; page++) page]);
  });
}
