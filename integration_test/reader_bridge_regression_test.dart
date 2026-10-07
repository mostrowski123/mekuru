// reader_bridge.js on a real web view (WKWebView on iOS, Chromium on
// Android), for behaviour only the bridge has: the text a selection reports,
// which taps count as on a character, and the chapter a position is in. The
// checks run in the page, not through taps, so they hold on both platforms
// (taps don't reach WKWebView in a test). One reader per file: see
// integration_test/shared/scroll_view_fixture.dart.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;

import 'shared/scroll_view_fixture.dart' show openReader;
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _title = 'ブリッジテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_bridge_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('selections, tap hits and chapter titles', (tester) async {
    // Scroll view, where a tap on an empty spot shows the controls. The
    // book's own ruby only (the default FuriganaMode.book): no generated
    // furigana reflowing the page under the measurements below.
    final db = createTestDatabase();
    addTearDown(db.close);
    final controller = await openReader(
      tester,
      await _writeEpub(tempDir),
      _title,
      db: db,
    );

    // A selection across ruby reports its base text, not the readings
    // ("羅生らしょう門もん…"), which would end up in a highlight's excerpt.
    await controller.debugEvaluateJavascript(
      '(function () {'
      '  window.__selections = [];'
      '  var send = window.callDart;'
      '  window.callDart = function (name, data) {'
      '    if (name === "selection") window.__selections.push(data.text);'
      '    return send.apply(this, arguments);'
      '  };'
      '  var doc = rendition.getContents()[0].document;'
      '  var range = doc.createRange();'
      '  range.selectNodeContents(doc.getElementById("ruby"));'
      '  var selection = doc.defaultView.getSelection();'
      '  selection.removeAllRanges();'
      '  selection.addRange(range);'
      '})()',
    );
    List<dynamic> selections = const [];
    for (var tick = 0; tick < 40 && selections.isEmpty; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      selections =
          (await evalJson(
                controller,
                'JSON.stringify({texts: window.__selections})',
              ))['texts']
              as List<dynamic>;
    }
    expect(selections, isNotEmpty, reason: 'no selection reached Dart');
    expect(selections.last, '羅生門が見える。');
    await controller.debugEvaluateJavascript(
      'rendition.getContents()[0].window.getSelection().removeAllRanges()',
    );

    // A tap counts as on a character only on or just beside its box. The
    // old check took anything within 50 px, so a tap in the gap above a line
    // (or in a margin beside it) looked up the nearest character.
    final hits = await evalJson(
      controller,
      '(function () {'
      '  var doc = rendition.getContents()[0].document;'
      '  var text = doc.getElementById("short").firstChild;'
      '  function box(index) {'
      '    var range = doc.createRange();'
      '    range.setStart(text, index);'
      '    range.setEnd(text, index + 1);'
      '    return range.getBoundingClientRect();'
      '  }'
      '  function hit(x, y) {'
      '    var found = getTextAtPoint(x, y, doc);'
      '    return found ? found.tappedChar : null;'
      '  }'
      '  var first = box(0), last = box(text.length - 1);'
      '  var x = (first.left + first.right) / 2;'
      '  var middle = (first.top + first.bottom) / 2;'
      '  return JSON.stringify({'
      '    onChar: hit(x, middle),'
      '    justAbove: hit(x, first.top - 4),'
      '    inGapAbove: hit(x, first.top - 25),'
      '    pastLineEnd: hit(last.right + 40, middle)'
      '  });'
      '})()',
    );
    expect(hits['onChar'], '短', reason: '$hits');
    expect(hits['justAbove'], '短', reason: '$hits');
    expect(hits['inGapAbove'], isNull, reason: '$hits');
    expect(hits['pastLineEnd'], isNull, reason: '$hits');

    // A bookmark's chapter: the TOC entry the position falls under, not the
    // book's last one, including a section anchored inside a file.
    final first = await evalJson(
      controller,
      'JSON.stringify({cfi: rendition.currentLocation().start.cfi})',
    );
    expect(await controller.chapterTitleAt(first['cfi'] as String), '第一章');

    await controller.debugEvaluateJavascript('rendition.display("c2.xhtml")');
    var shown = -1;
    for (var tick = 0; tick < 50 && shown != 1; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      shown =
          (await evalJson(
                controller,
                'JSON.stringify({index: rendition.currentLocation().start'
                ' ? rendition.currentLocation().start.index : -1})',
              ))['index']
              as int;
    }
    expect(shown, 1, reason: 'chapter 2 never displayed');
    final positions = await evalJson(
      controller,
      '(function () {'
      '  var contents = rendition.getContents().filter(function (c) {'
      '    return c.sectionIndex === 1;'
      '  })[0];'
      '  var doc = contents.document;'
      '  function cfiAt(id) {'
      '    var range = doc.createRange();'
      '    range.setStart(doc.getElementById(id).firstChild, 0);'
      '    range.collapse(true);'
      '    return contents.cfiFromRange(range);'
      '  }'
      '  return JSON.stringify({'
      '    start: cfiAt("c2-start"),'
      '    afterAnchor: cfiAt("after-anchor")'
      '  });'
      '})()',
    );
    expect(
      await controller.chapterTitleAt(positions['start'] as String),
      '第二章',
    );
    expect(
      await controller.chapterTitleAt(positions['afterAnchor'] as String),
      '第二章の後半',
    );

    // And Bookmark Page records that title. Only Android's web view takes
    // the tap (on the top margin) that shows the controls in a test.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final bookId = (await BookRepository(db).getAllBooks()).single.id;
      final viewer = tester.getRect(find.byType(CustomEpubViewer));
      await tester.tapAt(
        Offset(viewer.left + viewer.width * 0.15, viewer.top + 12),
      );
      final add = find.byTooltip(
        (await loadExpectedL10n()).readerBookmarkPageTooltip,
      );
      await pumpUntilVisible(tester, add);
      await tester.tap(add);
      final bookmarks = BookmarkRepository(db);
      for (var tick = 0; tick < 20; tick++) {
        await tester.pump(const Duration(milliseconds: 250));
        if ((await bookmarks.getBookmarksForBook(bookId)).isNotEmpty) break;
      }
      final saved = await bookmarks.getBookmarksForBook(bookId);
      expect(saved.single.chapterTitle, '第二章');
    }
  });
}

/// A two-chapter horizontal EPUB: ruby and a short line in chapter 1, and a
/// TOC whose nested entry points at an anchor in the middle of chapter 2.
Future<String> _writeEpub(Directory dir) async {
  final archive = Archive();

  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  String page(String title, String body) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
      '<!DOCTYPE html>'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja">'
      '<head><title>$title</title>'
      '<link href="style.css" rel="stylesheet" type="text/css"/>'
      '</head><body>$body</body></html>';

  const filler =
      '<p>山の中に深い穴がありました。村の人たちは、必要な時いつでもこの穴の口に'
      '来て、お椀やお皿を借りてくることにしていました。</p>';

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
        '<dc:title>$_title</dc:title>'
        '<dc:language>ja</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-000000000071</dc:identifier>'
        '</metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '</manifest>'
        '<spine><itemref idref="c1"/><itemref idref="c2"/></spine>'
        '</package>',
  );
  addFile('OEBPS/style.css', 'html { writing-mode: horizontal-tb; }\n');
  addFile(
    'OEBPS/nav.xhtml',
    page(
      '目次',
      '<nav epub:type="toc"><ol>'
          '<li><a href="c1.xhtml">第一章</a></li>'
          '<li><a href="c2.xhtml">第二章</a><ol>'
          '<li><a href="c2.xhtml#anchor">第二章の後半</a></li>'
          '</ol></li>'
          '</ol></nav>',
    ),
  );
  addFile(
    'OEBPS/c1.xhtml',
    page(
      'c1',
      '<p id="ruby"><ruby>羅生<rt>らしょう</rt></ruby>'
          '<ruby>門<rt>もん</rt></ruby>が見える。</p>'
          // The gap above keeps the line before far from a tap above.
          '<p id="short" style="margin-top: 6em">短い。</p>'
          '$filler',
    ),
  );
  addFile(
    'OEBPS/c2.xhtml',
    page(
      'c2',
      '<p id="c2-start">二章の始まり。</p>'
          '${filler * 3}'
          '<h2 id="anchor">後半</h2>'
          '<p id="after-anchor">後半の文。</p>',
    ),
  );

  final epubPath = p.join(dir.path, 'reader_bridge_fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}
