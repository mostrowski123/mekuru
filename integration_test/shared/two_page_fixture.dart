// Helpers for the two-page device tests: what the paginated reader shows,
// measured in the page.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';

import '../test_helpers.dart';

/// Where the reader is and what is on screen. `pos` is the scroll distance
/// from the section's start, `width` the screen (one pair). `left` and
/// `right` count the characters drawn on each half of the screen, `bad` the
/// ones that cross the fold or an edge of the screen, `sides` the halves the
/// text runs through in reading order ('RL': right page, then left).
/// `firstShown`/`lastShown`
/// say whether the location's start and end CFIs name the first and last
/// characters on screen (ruby annotations aside), `firstSide`/`lastSide`
/// which half they are on.
Future<Map<String, dynamic>> pairState(CustomEpubController controller) =>
    evalJson(controller, '''
(function () {
  var m = rendition.manager, c = m.container, C = c.getBoundingClientRect();
  var v = m.views.last(), l = rendition.location;
  if (!v || !v.contents || !l || !l.start) return JSON.stringify({pending: true});
  var doc = v.contents.document;
  var F = v.iframe.getBoundingClientRect();
  var mid =(C.left + C.right) / 2, left = 0, right = 0, bad = 0, sides = '';
  var first = null, last = null, r = doc.createRange();
  var walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT), node;
  while ((node = walker.nextNode())) {
    var ruby = node.parentElement && node.parentElement.closest('rt, rp');
    for (var i = 0; i < node.length; i++) {
      if (/\\s/.test(node.data[i])) continue;
      r.setStart(node, i); r.setEnd(node, i + 1);
      var b = r.getBoundingClientRect();
      if (!b.width) continue;
      var x0 = F.left + b.left, x1 = F.left + b.right;
      var y0 = F.top + b.top, y1 = F.top + b.bottom;
      if (x1 <= C.left + 1 || x0 >= C.right - 1) continue;
      if (x0 < C.left - 0.5 || x1 > C.right + 0.5 || y0 < C.top - 0.5 ||
          y1 > C.bottom + 0.5 || (x0 < mid && x1 > mid)) bad++;
      if (x0 + x1 < 2 * mid) left++; else right++;
      if (ruby) continue;
      var side = x0 + x1 < 2 * mid ? 'L' : 'R';
      if (sides.charAt(sides.length - 1) !== side) sides += side;
      if (!first) first = { node: node, i: i, side: side };
      last = { node: node, i: i, side: side };
    }
  }
  function named(cfi, end) {
    var range = cfi && new ePub.CFI(cfi).toRange(doc);
    if (!range || range.startContainer.nodeType !== 3) return null;
    var n = range.startContainer, o = range.startOffset;
    if (!end) {
      while (n && o >= n.length) { n = nextText(n); o = 0; }
      return n && { node: n, i: o };
    }
    return { node: n, i: o - 1 };
  }
  function nextText(n) {
    var w = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
    w.currentNode = n;
    return w.nextNode();
  }
  function same(a, b) { return !!a && !!b && a.node === b.node && a.i === b.i; }
  return JSON.stringify({
    divisor: m.layout.divisor, axis: m.settings.axis,
    index: l.start.index, page: l.start.displayed.page,
    endPage: l.end.displayed.page, total: l.start.displayed.total,
    pos: Math.round(Math.abs(c.scrollLeft)), width: c.offsetWidth,
    max: c.scrollWidth - c.offsetWidth,
    left: left, right: right, bad: bad, sides: sides,
    firstSide: first && first.side, lastSide: last && last.side,
    firstShown: same(named(l.start.cfi, false), first),
    lastShown: same(named(l.end.cfi, true), last),
    cfi: l.start.cfi
  });
})()
''');

/// [pairState] once the reader has settled after a re-layout: a section is
/// on screen, and two reads a moment apart agree.
Future<Map<String, dynamic>> settledPairState(
  WidgetTester tester,
  CustomEpubController controller,
) async {
  Map<String, dynamic>? last;
  for (var tick = 0; tick < 40; tick++) {
    await tester.pump(const Duration(milliseconds: 500));
    final state = await pairState(controller);
    if (state['pending'] == true) continue;
    if (last != null &&
        last['pos'] == state['pos'] &&
        last['divisor'] == state['divisor'] &&
        last['cfi'] == state['cfi']) {
      return state;
    }
    last = state;
  }
  throw TestFailure('The reader never settled: $last');
}

/// The CFI of the character at a point of the screen: [x] and [y] are
/// fractions of the screen's width and height.
Future<String> cfiAt(
  CustomEpubController controller,
  double x,
  double y,
) async {
  final json = await evalJson(controller, '''
(function () {
  var m = rendition.manager, C = m.container.getBoundingClientRect();
  var v = m.views.last(), doc = v.contents.document;
  var F = v.iframe.getBoundingClientRect();
  var r = doc.caretRangeFromPoint(C.left + $x * C.width - F.left,
    C.top + $y * C.height - F.top);
  return JSON.stringify({cfi: r ? v.contents.cfiFromRange(r) : null});
})()
''');
  return json['cfi'] as String;
}

/// Whether the character [cfi] names is on screen, and on which half.
Future<Map<String, dynamic>> charShown(
  CustomEpubController controller,
  String cfi,
) => evalJson(controller, '''
(function () {
  var m = rendition.manager, C = m.container.getBoundingClientRect();
  var v = m.views.last(), doc = v.contents.document;
  var F = v.iframe.getBoundingClientRect();
  var range = new ePub.CFI(${jsonEncode(cfi)}).toRange(doc);
  var n = range.startContainer, o = range.startOffset;
  // WebKit's caretRangeFromPoint (cfiAt) can put the caret after a text
  // node's last character: check that character.
  if (n.nodeType === 3 && o >= n.length) o = n.length - 1;
  var r = doc.createRange();
  r.setStart(n, o);
  r.setEnd(n, o + 1);
  var b = r.getBoundingClientRect();
  var x0 = F.left + b.left, x1 = F.left + b.right;
  return JSON.stringify({
    shown: x1 > C.left && x0 < C.right && b.width > 0,
    side: x0 + x1 < C.left + C.right ? 'L' : 'R',
    x: Math.round(x0 - C.left)
  });
})()
''');

/// Waits until the reader reports a location in section [index].
Future<void> waitForSection(
  WidgetTester tester,
  CustomEpubController controller,
  int index,
) async {
  for (var tick = 0; tick < 40; tick++) {
    await tester.pump(const Duration(milliseconds: 250));
    final state = await evalJson(
      controller,
      'JSON.stringify({index: rendition.location && rendition.location.start.index})',
    );
    if (state['index'] == index) {
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }
  throw TestFailure('Section $index never showed.');
}
