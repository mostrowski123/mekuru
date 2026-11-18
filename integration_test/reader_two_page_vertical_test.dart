// Two pages side by side for vertical text, with the screen sideways and the
// two-page switch on. The pages run leftwards, right page first; a turn moves
// a whole pair; no line is cut by the fold; the location names the first and
// last characters on screen; a saved place, a font change and generated
// furigana keep the pair; a picture of one page fills one page; and a web
// view that cannot page vertical text sideways keeps it on one page.
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

import 'shared/scroll_view_fixture.dart';
import 'shared/two_page_fixture.dart';
import 'test_helpers.dart';

const _title = '縦書き見開きテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_two_page_v_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('vertical text shows two pages, right page first', (
    tester,
  ) async {
    await MecabService.instance.init();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await tester.pump(const Duration(seconds: 2));

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(epubTwoPage: true),
    );
    await tester.pump(const Duration(seconds: 2));

    Future<Map<String, dynamic>> turn({bool back = false}) async {
      back ? controller.prev() : controller.next();
      await tester.pump(const Duration(milliseconds: 900));
      return pairState(controller);
    }

    void expectWholePair(Map<String, dynamic> pair) => expect(
      [pair['divisor'], pair['sides'], pair['bad']],
      [2, 'RL', 0],
      reason: '$pair',
    );

    // (a) Two pages, right page first: the text starts on the right half
    // and runs on to the left half.
    final start = await pairState(controller);
    expectWholePair(start);
    expect(start['firstSide'], 'R', reason: '$start');
    // (c) The location names the first and last characters on screen.
    expect([start['firstShown'], start['lastShown']], [true, true]);

    // (b, c, d) Every pair of chapter 1, then chapter 2 at its first pair.
    final total = start['total'] as int;
    final pages = <int>[start['page'] as int];
    var here = start;
    for (var turns = 0; turns < 40 && here['index'] == 0; turns++) {
      here = await turn();
      if (here['index'] != 0) break;
      expectWholePair(here);
      expect([here['firstShown'], here['lastShown']], [true, true]);
      pages.add(here['page'] as int);
    }
    expect(pages, [for (var page = 1; page < total; page += 2) page]);
    expect([here['index'], here['page'], here['pos']], [1, 1, 0]);
    final back = await turn(back: true);
    expect(back['index'], 0, reason: '$back');
    expect(back['endPage'], back['total'], reason: '$back');
    expect(back['pos'], closeTo(back['max'] as int, 1), reason: '$back');

    // (e) A place in a paragraph that runs on into the next pair opens on
    // the pair that holds it, not the one its paragraph ends on.
    Map<String, dynamic>? target;
    var pair = back;
    for (var turns = 0; turns < 8; turns++) {
      pair = await turn(back: true);
      target = await evalJson(controller, _lastCharsOnScreen);
      if (target['runsOn'] == true) break;
    }
    expect(target!['runsOn'], isTrue, reason: 'no paragraph ran on: $target');
    final cfi = target['cfi'] as String;
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.get(1).href); true',
    );
    await waitForSection(tester, controller, 1);
    await controller.debugEvaluateJavascript(
      'rendition.display(${jsonEncode(cfi)}); true',
    );
    await waitForSection(tester, controller, 0);
    final opened = await pairState(controller);
    expect(opened['pos'], pair['pos'], reason: 'target $target: $opened');
    expect((await charShown(controller, cfi))['shown'], isTrue);

    // (f) A bigger font keeps the first character on screen in view.
    final firstCfi = opened['cfi'] as String;
    await controller.debugEvaluateJavascript('setFontSize(22); true');
    await tester.pump(const Duration(seconds: 3));
    final bigger = await pairState(controller);
    expectWholePair(bigger);
    expect(
      (await charShown(controller, firstCfi))['shown'],
      isTrue,
      reason: 'first $firstCfi, after $bigger',
    );

    // (g) The image chapter: a picture of one page fills the pair's first
    // (right) page only.
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.get(2).href); true',
    );
    await waitForSection(tester, controller, 2);
    final image = await evalJson(controller, _imageBox);
    expect(image['divisor'], 2, reason: '$image');
    expect(image['width'], lessThanOrEqualTo(image['half']), reason: '$image');
    expect(
      image['left'],
      greaterThanOrEqualTo(image['half']),
      reason: '$image',
    );

    // (i) Generated furigana: still whole pairs, nothing across the fold.
    await controller.debugEvaluateJavascript(
      'rendition.display(book.spine.get(0).href); true',
    );
    await waitForSection(tester, controller, 0);
    controller.setFuriganaMode(FuriganaMode.all.storageValue);
    await waitForGeneratedRuby(tester, controller);
    await tester.pump(const Duration(seconds: 1));
    var ruby = await pairState(controller);
    for (var turns = 0; turns < 4; turns++) {
      expectWholePair(ruby);
      expect(ruby['firstShown'], isTrue, reason: '$ruby');
      ruby = await turn();
    }

    // (h) A web view that cannot page vertical text sideways: one page, as
    // today, while two pages are switched on.
    await controller.debugEvaluateJavascript(
      'window._twoPageVertical = false; true',
    );
    controller.setTwoPage(false);
    await tester.pump(const Duration(seconds: 2));
    controller.setTwoPage(true);
    await tester.pump(const Duration(seconds: 2));
    final single = await evalJson(controller, _verticalState);
    expect([single['axis'], single['divisor']], ['vertical', 1]);
    controller.next();
    await tester.pump(const Duration(milliseconds: 900));
    final down = await evalJson(controller, _verticalState);
    expect(
      (down['top'] as int) - (single['top'] as int),
      closeTo(single['height'] as int, 1),
      reason: 'before $single, after $down',
    );
  });
}

// The CFI of a character three before the last one on screen, and whether
// its text runs on past the screen.
const _lastCharsOnScreen = '''
(function () {
  var m = rendition.manager, C = m.container.getBoundingClientRect();
  var v = m.views.last(), doc = v.contents.document;
  var F = v.iframe.getBoundingClientRect();
  var walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT), node;
  var last = null, r = doc.createRange();
  while ((node = walker.nextNode())) {
    if (node.parentElement.closest('rt, rp')) continue;
    for (var i = 0; i < node.length; i++) {
      if (/\\s/.test(node.data[i])) continue;
      r.setStart(node, i); r.setEnd(node, i + 1);
      var b = r.getBoundingClientRect();
      if (b.width && F.left + b.right > C.left && F.left + b.left < C.right) {
        last = { node: node, i: i };
      }
    }
  }
  if (!last || last.i < 3) return JSON.stringify({ runsOn: false });
  r.setStart(last.node, last.i - 3); r.setEnd(last.node, last.i - 3);
  return JSON.stringify({
    cfi: v.contents.cfiFromRange(r),
    runsOn: /\\S/.test(last.node.data.slice(last.i + 1))
  });
})()
''';

const _imageBox = '''
(function () {
  var m = rendition.manager, C = m.container.getBoundingClientRect();
  var v = m.views.last(), img = v.contents.document.querySelector('img');
  var F = v.iframe.getBoundingClientRect(), b = img.getBoundingClientRect();
  return JSON.stringify({
    divisor: m.layout.divisor, half: Math.round(C.width / 2),
    left: Math.round(F.left + b.left - C.left), width: Math.round(b.width)
  });
})()
''';

const _verticalState = '''
(function () {
  var m = rendition.manager, c = m.container;
  return JSON.stringify({ axis: m.settings.axis, divisor: m.layout.divisor,
    top: Math.round(c.scrollTop), height: c.offsetHeight });
})()
''';
