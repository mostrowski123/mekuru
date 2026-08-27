import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// Integration test for the EPUB→manga conversion flow: long-press → options
/// sheet → confirm dialog → spinner → converted book routes to the manga
/// reader. Unit tests cover the converter itself; this exercises the real
/// import → convert → reader path on device.
const _containerXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> writeEpub(String name, List<ArchiveFile> files) async {
    final tempDir = await Directory.systemTemp.createTemp('convert_flow_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)),
      );
    files.forEach(archive.addFile);
    final path = '${tempDir.path}/$name';
    await File(path).writeAsBytes(ZipEncoder().encodeBytes(archive));
    return path;
  }

  /// Fixed-layout manga EPUB: [pageCount] single-image spine docs.
  Future<String> writeMangaEpub({int pageCount = 4}) {
    final manifest = StringBuffer();
    final spine = StringBuffer();
    final files = <ArchiveFile>[];
    for (var i = 0; i < pageCount; i++) {
      files
        ..add(
          ArchiveFile.bytes(
            'OEBPS/images/p$i.png',
            img.encodePng(img.Image(width: 10 + i, height: 100 + i)),
          ),
        )
        ..add(
          ArchiveFile.bytes(
            'OEBPS/page_$i.xhtml',
            utf8.encode(
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<html xmlns="http://www.w3.org/1999/xhtml">'
              '<head><title>p$i</title></head>'
              '<body><img src="images/p$i.png" alt=""/></body></html>',
            ),
          ),
        );
      manifest
        ..write('<item id="img$i" href="images/p$i.png" ')
        ..write('media-type="image/png"/>')
        ..write('<item id="page$i" href="page_$i.xhtml" ')
        ..write('media-type="application/xhtml+xml"/>');
      spine.write('<itemref idref="page$i"/>');
    }
    files.add(
      ArchiveFile.bytes(
        'OEBPS/content.opf',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:title>変換の本</dc:title><dc:language>ja</dc:language>'
          '</metadata>'
          '<manifest>$manifest</manifest>'
          '<spine page-progression-direction="rtl">$spine</spine>'
          '</package>',
        ),
      ),
    );
    return writeEpub('manga.epub', files);
  }

  /// Ordinary text EPUB — must be rejected by the converter.
  Future<String> writeTextEpub() => writeEpub('text.epub', [
    ArchiveFile.bytes(
      'OEBPS/content.opf',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>文章の本</dc:title></metadata>'
        '<manifest><item id="c1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c1"/></spine></package>',
      ),
    ),
    ArchiveFile.bytes(
      'OEBPS/chapter1.xhtml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><title>t</title></head><body><p>これは文章です。</p></body></html>',
      ),
    ),
  ]);

  Future<void> dismissSheet(WidgetTester tester) async {
    // Tap the modal barrier above the sheet.
    await tester.tapAt(const Offset(200, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'long-press → Convert to manga converts and routes to the manga reader',
    (tester) async {
      addTearDown(cleanupAppBooksDir);
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = BookRepository(db);
      final book = await repo.importEpub(await writeMangaEpub());

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      final tile = find.byKey(ValueKey('book-tile-${book.id}'));
      await pumpUntilVisible(tester, tile);

      await longPressTile(tester, tile);
      expect(find.text('Convert to manga'), findsOneWidget);
      await tapSheetItem(tester, 'Convert to manga');

      // Confirm dialog; Cancel is a no-op.
      expect(find.text('Convert to manga?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Converting…'), findsNothing);
      expect((await repo.getBookById(book.id))!.bookType, 'epub');

      // Convert for real.
      await longPressTile(tester, tile);
      await tapSheetItem(tester, 'Convert to manga');
      await tester.tap(find.text('Convert'));
      await pumpUntilVisible(
        tester,
        find.text('Converted to manga'),
        timeout: const Duration(seconds: 60),
      );
      // The snackbar shows while the spinner's pop animation may still be
      // running; wait for the route to actually leave the tree.
      await pumpUntilGone(tester, find.text('Converting…'));

      final converted = (await repo.getBookById(book.id))!;
      expect(converted.bookType, 'manga');
      expect(converted.totalPages, 4);

      // The sheet now offers the manga actions, not the EPUB ones.
      await pumpUntilGone(tester, find.text('Converted to manga'));
      await longPressTile(tester, tile);
      expect(find.text('Export as CBZ'), findsOneWidget);
      expect(find.text('Convert to manga'), findsNothing);
      expect(find.text('Export as EPUB'), findsNothing);
      await dismissSheet(tester);

      // Tapping the tile opens the manga reader.
      await tester.tap(tile);
      await pumpUntilVisible(tester, find.byType(MangaReaderScreen));
    },
  );

  testWidgets('a text EPUB is rejected and left untouched', (tester) async {
    addTearDown(cleanupAppBooksDir);
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);
    final book = await repo.importEpub(await writeTextEpub());

    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const LibraryScreen()),
    );
    final tile = find.byKey(ValueKey('book-tile-${book.id}'));
    await pumpUntilVisible(tester, tile);

    await longPressTile(tester, tile);
    await tapSheetItem(tester, 'Convert to manga');
    await tester.tap(find.text('Convert'));
    await pumpUntilVisible(
      tester,
      find.text(
        "This EPUB doesn't look like a manga — its pages aren't single images",
      ),
      timeout: const Duration(seconds: 60),
    );
    await pumpUntilGone(tester, find.text('Converting…'));

    final after = (await repo.getBookById(book.id))!;
    expect(after.bookType, 'epub');
    expect(Directory(after.filePath).existsSync(), isTrue);
  });
}
