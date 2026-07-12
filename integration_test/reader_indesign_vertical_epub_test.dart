// Regression test for InDesign-exported vertical EPUBs (e.g. the graded
// readers from jgrpg-sakura.com).
//
// Those books declare vertical writing only on <body> — and only via the
// `-epub-writing-mode` prefixed alias — while <html> stays horizontal-tb:
//
//   body { -epub-writing-mode: vertical-rl; }
//   div._idGenStoryDirection-1 { -epub-writing-mode: vertical-rl; }
//
// Blink honors the alias, so the body *renders* vertically, but stock
// epub.js reads the computed writing-mode of <html> only. It used to pick
// the horizontal pagination axis, apply `column-width` to the vertical
// body (splitting each page into stacked top/bottom blocks), and page
// turning skipped most of the book. The [MEKURU PATCH] in
// Contents.writingMode() falls back to the body's computed mode; this test
// locks that in end-to-end on a real WebView.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _title = '縦書きテスト';

Future<String> _writeInDesignStyleVerticalEpub(Directory dir) async {
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

  // Mirrors the JGR Sakura / InDesign structure: ja language, RTL page
  // progression, no primary-writing-mode meta, CSS with body-level
  // -epub-writing-mode only.
  addFile(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>$_title</dc:title>'
        '<dc:language>ja-JP</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-000000000001</dc:identifier>'
        '</metadata>'
        '<manifest>'
        '<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="css/idGeneratedStyles.css" media-type="text/css"/>'
        '</manifest>'
        '<spine page-progression-direction="rtl">'
        '<itemref idref="cover" linear="no"/>'
        '<itemref idref="chapter1"/>'
        '</spine>'
        '</package>',
  );

  // Non-linear cover as the first spine item, like InDesign exports. epub.js
  // gives non-linear sections no next()/prev() links, so the reader must NOT
  // start here (it could never page away).
  addFile(
    'OEBPS/cover.xhtml',
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
        '<!DOCTYPE html>'
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><title>cover</title></head>'
        '<body><p>表紙</p></body>'
        '</html>',
  );

  addFile(
    'OEBPS/css/idGeneratedStyles.css',
    'body { -epub-writing-mode: vertical-rl; -epub-hyphens: auto; }\n'
        'div._idGenStoryDirection-1 { -epub-writing-mode: vertical-rl; }\n'
        'p.body_1drop { font-size: 1em; text-indent: 1em; }\n',
  );

  final paragraph =
      '<p class="body_1drop">'
      '山の中に深い穴がありました。村の人たちは、必要な時いつでもこの穴の口に来て、'
      'お椀やお皿を借りてくることにしていました。長い山道を登って行くと、その穴があります。'
      '</p>';
  addFile(
    'OEBPS/chapter1.xhtml',
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
        '<!DOCTYPE html>'
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><title>chapter1</title>'
        '<link href="css/idGeneratedStyles.css" rel="stylesheet" type="text/css"/>'
        '</head>'
        '<body id="chapter1" lang="ja-JP">'
        '<div id="_idContainer001" class="_idGenStoryDirection-1">'
        // Enough text to span several pages on a phone-sized viewport.
        '${paragraph * 20}'
        '</div>'
        '</body>'
        '</html>',
  );

  final epubPath = p.join(dir.path, 'indesign_vertical_fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

Future<Map<String, dynamic>> _evalJson(
  CustomEpubController controller,
  String jsExpression,
) async {
  final raw = await controller.debugEvaluateJavascript(jsExpression);
  if (raw is String) {
    return jsonDecode(raw) as Map<String, dynamic>;
  }
  return (raw as Map).cast<String, dynamic>();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_indesign_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await cleanupAppBooksDir();
  });

  testWidgets(
    'body-level -epub-writing-mode EPUB paginates on the vertical axis',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final fixturePath = await _writeInDesignStyleVerticalEpub(tempDir);
      await BookRepository(db).importEpub(fixturePath);

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text(_title));

      await tester.tap(find.text(_title).first);
      await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
      await pumpUntilGone(
        tester,
        find.byKey(const Key('reader-loading-overlay')),
        timeout: const Duration(seconds: 20),
      );
      // Let the first section render settle.
      await tester.pump(const Duration(seconds: 1));

      final controller = tester
          .widget<CustomEpubViewer>(find.byType(CustomEpubViewer))
          .controller;

      final info = await _evalJson(
        controller,
        '(function () {'
        '  var view = rendition.manager.views._views[0];'
        '  return JSON.stringify({'
        '    writingMode: view.contents.writingMode(),'
        '    axis: rendition.manager.settings.axis,'
        '    cfi: rendition.currentLocation().start.cfi'
        '  });'
        '})()',
      );

      // The [MEKURU PATCH] must promote the body-level vertical writing mode
      // so epub.js paginates vertically instead of horizontally.
      expect(info['writingMode'], startsWith('vertical'));
      expect(info['axis'], 'vertical');

      // The reader must start on the linear chapter (spine index 1 → /6/4!),
      // not the non-linear cover — a non-linear section has no next() link
      // and would strand the reader on page one.
      expect(info['cfi'], contains('/6/4!'));

      // Page turning must advance within the chapter: the container scrolls
      // down by one page and the CFI moves. Before the fix, next() scrolled
      // horizontally through a mostly-empty layout and skipped the chapter.
      controller.next();
      await tester.pump(const Duration(seconds: 2));

      final after = await _evalJson(
        controller,
        '(function () {'
        '  var container = document.querySelector(".epub-container");'
        '  return JSON.stringify({'
        '    cfi: rendition.currentLocation().start.cfi,'
        '    scrollTop: container.scrollTop'
        '  });'
        '})()',
      );

      expect(after['cfi'], isNot(info['cfi']));
      expect((after['scrollTop'] as num).toDouble(), greaterThan(0));
    },
  );
}
