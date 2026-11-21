// A book whose links carry a '%' that does not percent-decode opens and
// pages through: chapter two's link escapes bytes that are not UTF-8
// (c%FF.xhtml, and its picture i%FF.png), chapter three's has a '%' that
// starts no escape (100%.xhtml). Each names its zip entry as it is written.
// epub.js used to throw URIError on them, and the reader never loaded. One
// reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '壊れた参照の本';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_bad_href_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a book whose links do not percent-decode opens and pages '
      'through', (tester) async {
    final controller = await openReader(
      tester,
      await _writeEpub(tempDir),
      _title,
      settings: const ReaderSettings(),
    );

    // Where the reader is, and what the section there shows.
    Future<Map<String, dynamic>> state() => evalJson(
      controller,
      '(function () {'
      '  var l = rendition.location.start;'
      '  var c = rendition.getContents().filter(function (c) {'
      '    return c.sectionIndex === l.index; })[0];'
      '  var img = c && c.document.querySelector("img");'
      '  return JSON.stringify({href: l.href, cfi: l.cfi,'
      '    title: c ? c.document.querySelector("h1").textContent : null,'
      '    picture: !!img && img.complete && img.naturalWidth > 0});'
      '})()',
    );
    Future<Map<String, dynamic>> until(
      bool Function(Map<String, dynamic> s) reached,
      String what,
    ) async {
      for (var i = 0; ; i++) {
        final s = await state();
        if (reached(s)) return s;
        if (i == 40) fail('$what: the reader is at $s');
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    final chapters = await controller.getChapters();
    expect(chapters.map((c) => c.href), [
      'c1.xhtml',
      'c%FF.xhtml#top',
      '100%.xhtml',
    ]);

    // The chapter list's link to chapter two, as a tap on it goes.
    controller.display(cfi: chapters[1].href);
    final two = await until(
      (s) => s['href'] == 'c%FF.xhtml' && s['picture'] == true,
      'chapter two and its picture i%FF.png, through the link',
    );
    expect(two['title'], '第二章');

    // A page turn inside chapter two, then on to chapter three.
    controller.next();
    final turned = await until(
      (s) => s['cfi'] != two['cfi'],
      'a page turn from chapter two',
    );
    expect(turned['href'], 'c%FF.xhtml', reason: 'chapter two has 2+ pages');
    for (var turns = 0; ; turns++) {
      if ((await state())['href'] == '100%.xhtml') break;
      if (turns == 10) fail('next() did not reach chapter three');
      final from = (await state())['cfi'];
      controller.next();
      await until((s) => s['cfi'] != from, 'a page turn');
    }
    expect((await state())['title'], '第三章');
    expect(find.byType(CustomEpubViewer), findsOneWidget);
  });
}

Future<String> _writeEpub(Directory dir) async {
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile.bytes(name, bytes));
  void addText(String name, String text) => add(name, utf8.encode(text));
  String chapter(String title, String body) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">'
      '<head><title>$title</title></head><body>$body</body></html>';
  final para = '<p>${'吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。' * 6}</p>';

  addText(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  addText(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>$_title</dc:title><dc:language>ja</dc:language></metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c%FF.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="100%.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="i" href="i%FF.png" media-type="image/png"/>'
        '</manifest><spine>'
        '<itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/>'
        '</spine></package>',
  );
  addText(
    'OEBPS/nav.xhtml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目次</title>'
        '</head><body><nav epub:type="toc"><ol>'
        '<li><a href="c1.xhtml">第一章</a></li>'
        '<li><a href="c%FF.xhtml#top">第二章</a></li>'
        '<li><a href="100%.xhtml">第三章</a></li>'
        '</ol></nav></body></html>',
  );
  addText('OEBPS/c1.xhtml', chapter('第一章', '<h1>第一章</h1>$para'));
  addText(
    'OEBPS/c%FF.xhtml',
    chapter(
      '第二章',
      '<h1 id="top">第二章</h1><p><img src="i%FF.png" alt=""/></p>'
          '${para * 6}',
    ),
  );
  addText('OEBPS/100%.xhtml', chapter('第三章', '<h1>第三章</h1>$para'));
  add(
    'OEBPS/i%FF.png',
    img.encodePng(
      img.Image(width: 60, height: 40)..clear(img.ColorRgb8(90, 90, 160)),
    ),
  );

  final path = p.join(dir.path, 'bad_href.epub');
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}
