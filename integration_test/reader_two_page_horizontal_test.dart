// Two pages side by side for horizontal text, with the screen sideways and
// the two-page switch on: a turn moves a whole pair, chapters change at
// their first and last pairs, and a saved place opens on the pair that holds
// it. One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/scroll_view_fixture.dart';
import 'shared/two_page_fixture.dart';
import 'test_helpers.dart';

const _title = '横書き見開きテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_two_page_h_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('horizontal text shows two pages and turns them in pairs', (
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
      settings: const ReaderSettings(epubTwoPage: true),
    );
    await tester.pump(const Duration(seconds: 2));

    Future<Map<String, dynamic>> turn({bool back = false}) async {
      back ? controller.prev() : controller.next();
      await tester.pump(const Duration(milliseconds: 900));
      return pairState(controller);
    }

    // (a) Two page-widths of text on screen.
    final start = await pairState(controller);
    expect(start['divisor'], 2, reason: '$start');
    expect(start['left'], greaterThan(0), reason: '$start');
    expect(start['right'], greaterThan(0), reason: '$start');
    expect(start['bad'], 0, reason: '$start');
    expect([start['firstShown'], start['lastShown']], [true, true]);

    // (b) One turn moves one screen, two pages.
    final second = await turn();
    expect(
      (second['pos'] as int) - (start['pos'] as int),
      closeTo(start['width'] as int, 1),
    );
    expect(second['page'], (start['page'] as int) + 2, reason: '$second');

    // (c) Every pair of the chapter, then chapter 2 at its first pair.
    final pages = <int>[start['page'] as int, second['page'] as int];
    var here = second;
    final total = start['total'] as int;
    for (var turns = 0; turns < 40 && here['index'] == 0; turns++) {
      expect(
        [here['firstShown'], here['lastShown'], here['bad']],
        [true, true, 0],
        reason: '$here',
      );
      here = await turn();
      if (here['index'] == 0) pages.add(here['page'] as int);
    }
    expect(pages, [for (var page = 1; page < total; page += 2) page]);
    expect([here['index'], here['page'], here['pos']], [1, 1, 0]);

    // (d) Back from chapter 2's first pair: chapter 1's last pair.
    final back = await turn(back: true);
    expect(back['index'], 0, reason: '$back');
    expect(back['endPage'], back['total'], reason: '$back');
    expect(back['pos'], closeTo(back['max'] as int, 1), reason: '$back');

    // (e) A place on either page of a middle pair opens on that pair.
    for (var turns = 0; turns < 4; turns++) {
      await turn(back: true);
    }
    final middle = await pairState(controller);
    for (final x in [0.25, 0.75]) {
      final cfi = await cfiAt(controller, x, 0.5);
      await controller.debugEvaluateJavascript(
        'rendition.display(book.spine.get(1).href); true',
      );
      await waitForSection(tester, controller, 1);
      await controller.debugEvaluateJavascript(
        'rendition.display(${jsonEncode(cfi)}); true',
      );
      await waitForSection(tester, controller, 0);
      final opened = await pairState(controller);
      expect(opened['pos'], middle['pos'], reason: 'x $x: $opened');
      expect((await charShown(controller, cfi))['shown'], isTrue);
    }

    // (f) Switched off: the same window shows one page, at the same place,
    // even when the switch comes while the book is still opening (no view
    // manager yet).
    final firstCfi = (await pairState(controller))['cfi'] as String;
    await controller.debugEvaluateJavascript(
      '(function () {'
      '  var m = rendition.manager;'
      '  rendition.manager = null;'
      '  setTwoPage(null);'
      '  rendition.manager = m;'
      '  return true;'
      '})()',
    );
    await tester.pump(const Duration(seconds: 2));
    final single = await settledPairState(tester, controller);
    expect(single['divisor'], 1, reason: '$single');
    expect((await charShown(controller, firstCfi))['shown'], isTrue);
  });
}
