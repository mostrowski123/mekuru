// The reader's font setting overrides the fonts an EPUB's own CSS sets, and
// going back to "Book default" brings them back in the open chapter. epub.js
// appends theme rules to the chapter's theme stylesheet instead of replacing
// them, so without the reset in reader_bridge.js updateTheme() the override
// would stay until the chapter re-rendered.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _title = 'フォントテスト';

Future<String> _writeEpubWithOwnFont(Directory dir) async {
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
        '<dc:title>$_title</dc:title>'
        '<dc:language>ja</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-000000000002</dc:identifier>'
        '</metadata>'
        '<manifest>'
        '<item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '</manifest>'
        '<spine page-progression-direction="rtl">'
        '<itemref idref="chapter1"/>'
        '</spine>'
        '</package>',
  );
  // A class-level font, as Japanese EPUBs often set: a body-only override
  // would not reach it.
  addFile('OEBPS/style.css', 'p.own { font-family: monospace; }\n');
  addFile(
    'OEBPS/chapter1.xhtml',
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
        '<!DOCTYPE html>'
        '<html xmlns="http://www.w3.org/1999/xhtml" lang="ja">'
        '<head><title>chapter1</title>'
        '<link href="style.css" rel="stylesheet" type="text/css"/>'
        '</head>'
        '<body><p class="own">山の中に深い穴がありました。</p></body>'
        '</html>',
  );

  final epubPath = p.join(dir.path, 'font_family_fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

const _paragraphFont =
    '(function () {'
    '  var doc = rendition.getContents()[0].document;'
    '  var p = doc.querySelector("p.own");'
    '  return JSON.stringify({font: doc.defaultView.getComputedStyle(p).fontFamily});'
    '})()';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_font_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await cleanupAppBooksDir();
  });

  testWidgets('font setting overrides the book font and can be undone', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await BookRepository(db).importEpub(await _writeEpubWithOwnFont(tempDir));

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
    await tester.pump(const Duration(seconds: 1));

    final controller = tester
        .widget<CustomEpubViewer>(find.byType(CustomEpubViewer))
        .controller;
    final settings = ProviderScope.containerOf(
      tester.element(find.byType(CustomEpubViewer)),
    ).read(readerSettingsProvider.notifier);

    expect((await evalJson(controller, _paragraphFont))['font'], 'monospace');

    settings.setFontFamily(ReaderFontFamily.mincho);
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await evalJson(controller, _paragraphFont))['font'],
      contains('Hiragino Mincho ProN'),
    );

    settings.setFontFamily(ReaderFontFamily.book);
    await tester.pump(const Duration(seconds: 2));
    expect((await evalJson(controller, _paragraphFont))['font'], 'monospace');

    // The bridge on its own, with no re-layout in between: a rule the new
    // theme drops must stop applying to the open chapter.
    final dropped = await evalJson(
      controller,
      '(function () {'
      '  updateTheme("", {"body *": {"font-family": "serif !important"}});'
      '  updateTheme("", {});'
      '  return $_paragraphFont;'
      '})()',
    );
    expect(dropped['font'], 'monospace');
  });
}
