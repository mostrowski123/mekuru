// Scroll view on a real WebView, one scenario per text direction. Each test
// file registers one scenario: WebView input is unreliable in the second
// reader of a process (Serena memory integration_test_webview_tap_limitations).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;

import '../test_helpers.dart';
import 'test_infrastructure.dart';

/// Registers the scroll-view scenario. [vertical] books are vertical-rl and
/// scroll sideways (right to left); the others are horizontal-tb and scroll
/// up and down. The scenario covers one-screen steps, the reported location,
/// reading-stats counts, the start position being the first visible line
/// (the per-character Mapping [MEKURU PATCH]), the display(cfi) round trip
/// (moveToTarget(); without it a resumed vertical book opens at the end of
/// its chapter), chapter changes at both ends without a flash of the wrong
/// layout (expand() sizing patch), no side margins, and an image page that
/// fits one screen (adjustImages() patch).
void registerScrollViewScenario({required bool vertical}) {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_scroll_view_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets(
    vertical
        ? 'vertical text scrolls sideways chapter by chapter'
        : 'horizontal text scrolls up and down chapter by chapter',
    (tester) async {
      final controller = await openReader(
        tester,
        await writeScrollViewEpub(
          tempDir,
          title: _title(vertical),
          vertical: vertical,
        ),
        _title(vertical),
      );

      Future<Map<String, dynamic>> settle() async {
        await tester.pump(const Duration(milliseconds: 1500));
        return _scrollState(controller);
      }

      // Moves the strip with epub.js's own scrollBy, which flips the sign
      // for right-to-left text. Browsers clamp, so 100 screens reach an end.
      Future<void> scrollScreens(num screens) =>
          controller.debugEvaluateJavascript(
            '(function () {'
            '  var m = rendition.manager, c = m.container;'
            '  if (m.settings.axis === "vertical") {'
            '    m.scrollBy(0, $screens * c.clientHeight);'
            '  } else {'
            '    m.scrollBy($screens * c.clientWidth, 0);'
            '  }'
            '})()',
          );

      await _recordPageChars(controller);
      final start = await _scrollState(controller);
      expect(start['flow'], 'scrolled');
      expect(start['axis'], vertical ? 'horizontal' : 'vertical');
      if (vertical) expect(start['dir'], 'rtl');
      expect(start['index'], 0);
      expect(start['atStart'], isTrue, reason: '$start');
      expect(start['atEnd'], isFalse, reason: '$start');
      // No side margins: the text runs to the screen edges.
      expect(start['sideMargin'], 0, reason: '$start');

      // next() mid-chapter moves one screen, not a chapter, and reports the
      // new place even as the first scroll after the chapter opened.
      controller.next();
      final stepped = await settle();
      expect(stepped['index'], 0);
      expect(stepped['reportedCfi'], stepped['cfi'], reason: '$stepped');
      expect(
        (stepped['pos'] as num) - (start['pos'] as num),
        closeTo(start['screen'] as num, 2),
        reason: 'start $start, stepped $stepped',
      );

      // Scrolling on reveals later text: the location follows.
      await scrollScreens(1);
      final scrolled = await settle();
      expect(
        await _compareCfi(controller, scrolled['cfi'], stepped['cfi']),
        1,
        reason: 'before $stepped, after $scrolled',
      );

      // Reading stats: each settle counts only text not counted before, so
      // scrolling back reports nothing.
      final counts = await _recordedPageChars(controller);
      expect(counts, hasLength(2), reason: '$counts');
      expect(counts.every((c) => c > 0), isTrue, reason: '$counts');
      await scrollScreens(-1);
      await settle();
      expect(await _recordedPageChars(controller), counts);

      // The start position is the first line on screen, even mid-paragraph
      // (a paragraph here spans several lines).
      await scrollScreens(1.37);
      final left = await settle();
      expect(left['firstLine'], inInclusiveRange(0, 1), reason: '$left');

      // display(cfi) returns to that exact line from the chapter start: the
      // saved start CFI comes back as the start CFI, so resuming never creeps.
      final savedCfi = left['cfi'] as String;
      await scrollScreens(-100);
      await settle();
      controller.display(cfi: savedCfi);
      final restored = await settle();
      expect(restored['index'], 0);
      expect(restored['atStart'], isFalse, reason: '$restored');
      expect(restored['atEnd'], isFalse, reason: '$restored');
      expect(
        restored['firstLine'],
        inInclusiveRange(0, 1),
        reason: '$restored',
      );
      expect(
        await _compareCfi(controller, restored['cfi'], savedCfi),
        0,
        reason: 'saved $savedCfi, restored $restored',
      );

      // At the end of the strip, next() loads the next chapter at its start.
      await scrollScreens(100);
      final atEnd = await settle();
      expect(atEnd['atEnd'], isTrue, reason: '$atEnd');
      controller.next();
      final chapter2 = await settle();
      expect(chapter2['index'], 1, reason: '$chapter2');
      expect(chapter2['atStart'], isTrue, reason: '$chapter2');

      // At the start of a chapter, prev() loads the previous one at its end,
      // never showing its start or a wrongly measured layout on the way.
      // Only shown frames count: the view stays hidden while it is measured
      // (on iOS the first hidden frame is about twice the final width).
      await _recordFrames(controller);
      controller.prev();
      final back = await settle();
      expect(back['index'], 0, reason: '$back');
      expect(back['atEnd'], isTrue, reason: '$back');
      final frames = (await _recordedFrames(
        controller,
      )).where((f) => f['index'] == 0 && f['visible'] == true).toList();
      expect(frames, isNotEmpty);
      expect(
        frames.where((f) => f['atStart'] == true),
        isEmpty,
        reason: 'the chapter start flashed: $frames',
      );
      expect(
        frames.map((f) => f['length'] as num).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo((back['length'] as num) + 1),
        reason: 'a wrongly measured layout showed: $frames',
      );

      // An image page taller than the screen still fits on one screen.
      await controller.debugEvaluateJavascript(
        'rendition.display(book.spine.get(2).href)',
      );
      final image = await settle();
      expect(image['index'], 2, reason: '$image');
      expect(image['atStart'] && image['atEnd'], isTrue, reason: '$image');
    },
  );
}

String _title(bool vertical) => vertical ? '縦スクロールテスト' : '横スクロールテスト';

/// Writes a two-chapter EPUB, each chapter several screens long. [vertical]
/// books are vertical-rl with rtl page progression; the others are plain
/// horizontal-tb.
Future<String> writeScrollViewEpub(
  Directory dir, {
  required String title,
  required bool vertical,
}) async {
  final archive = Archive();

  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addFile(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
        '</rootfiles>'
        '</container>',
  );
  addFile(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>$title</dc:title>'
        '<dc:language>ja</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-00000000005${vertical ? 1 : 2}</dc:identifier>'
        '</metadata>'
        '<manifest>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="tall" href="tall.svg" media-type="image/svg+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '</manifest>'
        '<spine${vertical ? ' page-progression-direction="rtl"' : ''}>'
        '<itemref idref="c1"/>'
        '<itemref idref="c2"/>'
        '<itemref idref="c3"/>'
        '</spine>'
        '</package>',
  );
  addFile(
    'OEBPS/style.css',
    vertical
        ? 'html { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }\n'
        : 'html { writing-mode: horizontal-tb; }\n',
  );

  // Long paragraphs so every line is full (see the tap-limitations memory).
  final paragraph =
      '<p>'
      '山の中に深い穴がありました。村の人たちは、必要な時いつでもこの穴の口に来て、'
      'お椀やお皿を借りてくることにしていました。長い山道を登って行くと、その穴があります。'
      '穴の前で頭を下げて、明日はお客が来ますからお椀を十貸してくださいと頼みます。'
      '</p>';
  for (final chapter in ['c1', 'c2']) {
    addFile(
      'OEBPS/$chapter.xhtml',
      '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
          '<!DOCTYPE html>'
          '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">'
          '<head><title>$chapter</title>'
          '<link href="style.css" rel="stylesheet" type="text/css"/>'
          '</head>'
          '<body>${paragraph * 30}</body>'
          '</html>',
    );
  }

  // An image page like a converted light novel's illustrations: a
  // horizontal-tb section holding one image taller than any screen.
  addFile(
    'OEBPS/tall.svg',
    '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="4000">'
        '<rect width="400" height="4000" fill="#88a"/></svg>',
  );
  addFile(
    'OEBPS/c3.xhtml',
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
        '<!DOCTYPE html>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja" '
        'style="writing-mode: horizontal-tb">'
        '<head><title>c3</title></head>'
        '<body><p><img src="tall.svg" alt=""/></p></body>'
        '</html>',
  );

  final epubPath = p.join(dir.path, 'scroll_view_fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

/// Imports [epubPath], opens it with [settings] and waits for the first
/// chapter to render. Returns the viewer's controller.
Future<CustomEpubController> openReader(
  WidgetTester tester,
  String epubPath,
  String title, {
  ReaderSettings settings = const ReaderSettings(scrollView: true),
}) async {
  final db = createTestDatabase();
  addTearDown(db.close);
  await BookRepository(db).importEpub(epubPath);

  final storage = InMemoryReaderSettingsStorage();
  await storage.save(settings);

  await tester.pumpWidget(
    buildIntegrationTestApp(
      db: db,
      home: const LibraryScreen(),
      readerSettingsStorage: storage,
    ),
  );
  await pumpUntilVisible(tester, find.text(title));
  await tester.tap(find.text(title).first);
  await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
  await pumpUntilGone(
    tester,
    find.byKey(const Key('reader-loading-overlay')),
    timeout: const Duration(seconds: 20),
  );
  await tester.pump(const Duration(seconds: 1));
  return tester
      .widget<CustomEpubViewer>(find.byType(CustomEpubViewer))
      .controller;
}

/// The reader's scroll-view state. `pos` is the distance scrolled from the
/// start of the strip and `screen` one screen's length, both along its axis.
Future<Map<String, dynamic>> _scrollState(CustomEpubController controller) =>
    evalJson(
      controller,
      '(function () {'
      '  var m = rendition.manager, c = m.container;'
      '  var vertical = m.settings.axis === "vertical";'
      '  var e = scrollEdges();'
      '  var loc = rendition.currentLocation();'
      '  var v = m.views.last();'
      '  var box = v.contents.charBox(loc.start.cfi);'
      '  var frame = v.iframe.getBoundingClientRect();'
      '  var edge = c.getBoundingClientRect();'
      '  var firstLine = box && (vertical'
      '    ? (frame.top + box.rect.top - edge.top) / box.line'
      '    : (edge.right - frame.left - box.rect.right) / box.line);'
      '  return JSON.stringify({'
      '    sideMargin: edge.left,'
      '    firstLine: firstLine,'
      '    length: vertical ? c.scrollHeight : c.scrollWidth,'
      '    flow: rendition.settings.flow,'
      '    axis: m.settings.axis,'
      '    dir: m.settings.direction,'
      '    atStart: e.atStart,'
      '    atEnd: e.atEnd,'
      '    pos: vertical ? c.scrollTop : Math.abs(c.scrollLeft),'
      '    screen: vertical ? c.clientHeight : c.clientWidth,'
      '    index: loc.start.index,'
      '    cfi: loc.start.cfi,'
      '    reportedCfi: rendition.location && rendition.location.start.cfi'
      '  });'
      '})()',
    );

/// Records, on every animation frame for 3 s, the displayed section, whether
/// the strip is visible, whether it sits at its start, and its length.
Future<void> _recordFrames(
  CustomEpubController controller,
) => controller.debugEvaluateJavascript(
  '(function () {'
  '  window._frames = [];'
  '  var t0 = performance.now();'
  '  (function tick() {'
  '    var m = rendition.manager, c = m.container, v = m.views.last();'
  '    var vertical = m.settings.axis === "vertical";'
  '    window._frames.push({'
  '      index: v ? v.section.index : -1,'
  '      visible: !!v && getComputedStyle(v.element).visibility !== "hidden",'
  '      atStart: scrollEdges().atStart,'
  '      length: vertical ? c.scrollHeight : c.scrollWidth'
  '    });'
  '    if (performance.now() - t0 < 3000) requestAnimationFrame(tick);'
  '  })();'
  '})()',
);

Future<List<Map<String, dynamic>>> _recordedFrames(
  CustomEpubController controller,
) async {
  final json = await evalJson(
    controller,
    'JSON.stringify({frames: window._frames})',
  );
  return (json['frames'] as List).cast<Map<String, dynamic>>();
}

/// Starts recording the counts of the bridge's `pageChars` reports (the
/// reading-stats character counts) sent from now on.
Future<void> _recordPageChars(CustomEpubController controller) =>
    controller.debugEvaluateJavascript(
      '(function () {'
      '  window._pageCharsLog = [];'
      '  var bridge = window.flutter_inappwebview;'
      '  var original = bridge.callHandler;'
      '  bridge.callHandler = function (name, data) {'
      '    if (name === "pageChars") window._pageCharsLog.push(data.count);'
      '    return original.apply(bridge, arguments);'
      '  };'
      '})()',
    );

/// Counts recorded since [_recordPageChars].
Future<List<int>> _recordedPageChars(CustomEpubController controller) async {
  final json = await evalJson(
    controller,
    'JSON.stringify({counts: window._pageCharsLog})',
  );
  return (json['counts'] as List).cast<num>().map((c) => c.toInt()).toList();
}

/// -1, 0 or 1 as epub.js orders two CFIs.
Future<int> _compareCfi(
  CustomEpubController controller,
  String a,
  String b,
) async {
  final raw = await controller.debugEvaluateJavascript(
    'new ePub.CFI().compare(${jsonEncode(a)}, ${jsonEncode(b)})',
  );
  return (raw as num).toInt();
}
