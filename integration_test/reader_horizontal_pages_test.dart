// Turning pages in horizontal text with the screen sideways. Scroll
// positions snap to device pixels and each turn adds to the last snapped
// position, so after a dozen turns a page started a pixel or two before its
// boundary, and the page counter numbered it as the page before.
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '横書きページテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_horizontal_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('every page of a horizontal chapter is shown and counted', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await tester.pump(const Duration(seconds: 2));

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: false),
      _title,
      settings: const ReaderSettings(),
    );
    await controller.debugEvaluateJavascript('setFontSize(26); true');
    await tester.pump(const Duration(seconds: 2));
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.get(0).href); true',
    );
    await tester.pump(const Duration(seconds: 2));

    final shown = <int>[];
    final counted = <int>[];
    var pages = 0;
    for (var turn = 0; turn < 80; turn++) {
      final here = await evalJson(
        controller,
        '(function () {'
        '  var c = rendition.manager.container;'
        '  return JSON.stringify({'
        '    index: rendition.currentLocation().start.index,'
        '    counted: rendition.location.start.displayed.page,'
        '    page: Math.round(Math.abs(c.scrollLeft) / c.offsetWidth) + 1,'
        '    pages: Math.round(c.scrollWidth / c.offsetWidth)});'
        '})()',
      );
      if (here['index'] != 0) break;
      shown.add(here['page'] as int);
      counted.add(here['counted'] as int);
      pages = here['pages'] as int;
      controller.next();
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(pages, greaterThan(2), reason: 'needs a few pages');
    expect(shown, [for (var page = 1; page <= pages; page++) page]);
    // The page counter (the reader's progress within a chapter) agrees.
    expect(counted, shown);
  });
}
