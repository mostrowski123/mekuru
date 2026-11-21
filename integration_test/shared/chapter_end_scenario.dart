// Paging back from a chapter's first page, and jumping to a place on the last
// page of another chapter, on a real WebView. epub.js sized a new chapter
// before the reader's font size and theme re-laid it out, and measured it
// again only a frame or two later, so both could land one or two pages before
// the chapter's end: the reader skipped those pages, and Dart saved that page
// as the progress and counted its characters as read.
//
// Each test file registers one scenario: a second reader in one process
// misbehaves (see scroll_view_fixture.dart).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:path/path.dart' as p;

import '../test_helpers.dart';
import 'scroll_view_fixture.dart' show openReader;

void registerChapterEndScenario({required bool vertical}) {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_chapter_end_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets(
    '${vertical ? 'vertical' : 'horizontal'} text: going back a chapter '
    "lands on that chapter's last page",
    (tester) async {
      final title = vertical ? '縦章末テスト' : '横章末テスト';
      final controller = await openReader(
        tester,
        await _writeEpub(tempDir, title: title, vertical: vertical),
        title,
        settings: vertical
            ? const ReaderSettings()
            : const ReaderSettings(
                verticalText: false,
                readingDirection: ReaderDirection.ltr,
              ),
      );
      await _recordReports(controller);

      // Back into c1 (text only) and into c2 (text, then an image whose size
      // is known only once it loads).
      for (final (from, into) in [('c2.xhtml', 0), ('c3.xhtml', 1)]) {
        controller.display(cfi: from); // what a table-of-contents tap runs
        final start = await _settled(tester, controller);
        expect(start['index'], into + 1, reason: 'display($from): $start');

        await _clearReports(controller);
        controller.prev(); // what a backward page turn runs
        final back = await _settled(tester, controller);
        expect(back['index'], into, reason: 'previous() from $from: $back');
        expect(
          back['page'],
          back['total'],
          reason: 'previous() from $from landed before the last page: $back',
        );
        // What Dart saves as the place in the book, and the page whose
        // characters it counts as read.
        final reports = await _reports(controller);
        final located = reports.where((r) => r['name'] == 'relocated');
        expect(located, isNotEmpty, reason: 'no relocated after previous()');
        expect(located.last['cfi'], back['cfi'], reason: '$reports');
        expect(located.last['progress'], back['progress'], reason: '$reports');
        expect(
          [
            for (final r in reports)
              if (r['name'] == 'pageChars') r['cfi'],
          ],
          [back['cfi']],
          reason: 'pageChars after previous(): $reports',
        );

        controller.next();
        final forward = await _settled(tester, controller);
        expect(
          forward['index'],
          into + 1,
          reason:
              'one page on from the landing stayed in the chapter: $forward',
        );

        // A bookmark or search hit on that last page, opened from elsewhere.
        controller.display(cfi: from);
        await _settled(tester, controller);
        controller.display(cfi: back['cfi'] as String);
        final jumped = await _settled(tester, controller);
        expect(
          [jumped['cfi'], jumped['page']],
          [back['cfi'], back['total']],
          reason: 'jump to ${back['cfi']} from $from: $jumped',
        );
      }
    },
  );
}

const _paragraph =
    '<p>山の中に深い穴がありました。村の人たちは、必要な時いつでもこの穴の口に来て、'
    'お椀やお皿を借りてくることにしていました。長い山道を登って行くと、その穴があります。'
    '穴の前で頭を下げて、明日はお客が来ますからお椀を十貸してくださいと頼みます。</p>';

/// Four chapters, the first three several pages long at any phone size.
Future<String> _writeEpub(
  Directory dir, {
  required String title,
  required bool vertical,
}) async {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>$title</dc:title><dc:language>ja</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-0000000ce00${vertical ? 1 : 2}</dc:identifier>'
        '</metadata><manifest>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c4" href="c4.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="pic" href="pic.svg" media-type="image/svg+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '</manifest>'
        '<spine${vertical ? ' page-progression-direction="rtl"' : ''}>'
        '<itemref idref="c1"/><itemref idref="c2"/>'
        '<itemref idref="c3"/><itemref idref="c4"/></spine></package>',
  );
  add(
    'OEBPS/style.css',
    vertical
        ? 'html { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }\n'
        : 'html { writing-mode: horizontal-tb; }\n',
  );
  add(
    'OEBPS/pic.svg',
    '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800">'
        '<rect width="600" height="800" fill="#8a8"/></svg>',
  );
  String chapter(String name, String body) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="no"?><!DOCTYPE html>'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">'
      '<head><title>$name</title>'
      '<link href="style.css" rel="stylesheet" type="text/css"/></head>'
      '<body><h1>$name</h1>$body</body></html>';
  add('OEBPS/c1.xhtml', chapter('第一章', _paragraph * 40));
  add(
    'OEBPS/c2.xhtml',
    chapter(
      '第二章',
      '${_paragraph * 36}<p><img src="pic.svg" alt=""/></p>$_paragraph',
    ),
  );
  add('OEBPS/c3.xhtml', chapter('第三章', _paragraph * 40));
  add('OEBPS/c4.xhtml', chapter('第四章', _paragraph * 3));
  final path = p.join(dir.path, 'chapter_end_${vertical ? 'v' : 'h'}.epub');
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}

// Where the reader is, from the scroll position: the spine index, the page
// of its chapter (1-based) and the page count, and the start CFI and the
// progress the bridge reports for it.
const _locationJs =
    '(function () {'
    '  var s = rendition.currentLocation().start;'
    '  return JSON.stringify({index: s.index, page: s.displayed.page,'
    '    total: s.displayed.total, cfi: s.cfi, progress: s.percentage});'
    '})()';

/// Polls until the location reads the same twice, 400 ms apart.
Future<Map<String, dynamic>> _settled(
  WidgetTester tester,
  CustomEpubController controller,
) async {
  var last = '';
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 400));
    final now = jsonEncode(await evalJson(controller, _locationJs));
    if (now == last) break;
    last = now;
  }
  return jsonDecode(last) as Map<String, dynamic>;
}

/// Records the bridge's `relocated` and `pageChars` calls to Dart from now on.
Future<void> _recordReports(CustomEpubController controller) =>
    controller.debugEvaluateJavascript(
      '(function () {'
      '  window._reports = [];'
      '  var bridge = window.flutter_inappwebview;'
      '  var original = bridge.callHandler;'
      '  bridge.callHandler = function (name, data) {'
      '    if (name === "relocated") window._reports.push({name: name,'
      '      cfi: data.startCfi, progress: data.progress});'
      '    if (name === "pageChars") window._reports.push({name: name,'
      '      cfi: data.pageKey});'
      '    return original.apply(bridge, arguments);'
      '  };'
      '})()',
    );

Future<void> _clearReports(CustomEpubController controller) =>
    controller.debugEvaluateJavascript('window._reports.length = 0');

Future<List<Map<String, dynamic>>> _reports(
  CustomEpubController controller,
) async {
  final json = await evalJson(
    controller,
    'JSON.stringify({reports: window._reports})',
  );
  return (json['reports'] as List).cast<Map<String, dynamic>>();
}
