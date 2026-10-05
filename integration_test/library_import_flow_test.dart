import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/library/presentation/widgets/book_cover_image.dart';
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

Future<String> _writeFixtureEpub(Directory dir, {required String title}) async {
  final archive = Archive();

  final containerXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles>'
      '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles>'
      '</container>';
  final containerBytes = utf8.encode(containerXml);
  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      containerBytes.length,
      containerBytes,
    ),
  );

  final opfXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title>'
      '<dc:language>ja</dc:language>'
      '</metadata>'
      '<manifest>'
      '<item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="chapter1"/></spine>'
      '</package>';
  final opfBytes = utf8.encode(opfXml);
  archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

  final chapterBytes = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>Chapter 1</title></head>'
    '<body><p>テスト。</p></body>'
    '</html>',
  );
  archive.addFile(
    ArchiveFile('OEBPS/chapter1.xhtml', chapterBytes.length, chapterBytes),
  );

  final epubPath = p.join(dir.path, 'fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_import_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await cleanupAppBooksDir();
  });

  testWidgets(
    'importEpub parses metadata, persists the book, and renders it in the library grid',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final fixturePath = await _writeFixtureEpub(tempDir, title: '走れメロス');

      final imported = await BookRepository(db).importEpub(fixturePath);
      expect(imported.title, '走れメロス');
      expect(imported.language, 'ja');

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text('走れメロス'));

      // The tile renders the title in two text styles (label + body) for
      // layout reasons, so >=1 is the right assertion here.
      expect(find.text('走れメロス'), findsAtLeastNWidgets(1));
      expect(find.byType(LibraryScreen), findsOneWidget);
    },
  );

  testWidgets('importing two EPUBs renders both tiles in the grid', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final repo = BookRepository(db);
    final firstPath = await _writeFixtureEpub(
      Directory(p.join(tempDir.path, 'a'))..createSync(),
      title: 'こころ',
    );
    final secondPath = await _writeFixtureEpub(
      Directory(p.join(tempDir.path, 'b'))..createSync(),
      title: '坊っちゃん',
    );

    await repo.importEpub(firstPath);
    await repo.importEpub(secondPath);

    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const LibraryScreen()),
    );
    await pumpUntilVisible(tester, find.text('こころ'));

    expect(find.text('こころ'), findsAtLeastNWidgets(1));
    expect(find.text('坊っちゃん'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'batch importFiles imports every file and shows the batch summary',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final firstPath = await _writeFixtureEpub(
        Directory(p.join(tempDir.path, 'a'))..createSync(),
        title: 'こころ',
      );
      final secondPath = await _writeFixtureEpub(
        Directory(p.join(tempDir.path, 'b'))..createSync(),
        title: '吾輩は猫である',
      );

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );

      final imported = await container
          .read(bookImportProvider.notifier)
          .importFiles([firstPath, secondPath], format: 'epub');
      expect(imported, 2);

      // Check the banner first: it auto-dismisses after 5s of real time,
      // which can elapse while pumping for the grid tiles below.
      await tester.pump();
      expect(find.text('Imported 2 books'), findsOneWidget);

      await pumpUntilVisible(tester, find.text('こころ'));
      expect(find.text('こころ'), findsAtLeastNWidgets(1));
      expect(find.text('吾輩は猫である'), findsAtLeastNWidgets(1));

      // Cancel the success banner's auto-dismiss timer while the container
      // is still alive (reading it in addTearDown would throw — the widget
      // tree and its container are disposed before teardowns run).
      container.read(bookImportProvider.notifier).clearState();
      await tester.pump();
    },
  );

  // The user's flow on iOS: Import Manga > Mokuro folder > pick a folder
  // (native picker, mocked here) > tap the .html in the list. iOS copies the
  // pages into the app, and a folder missing one page made that copy throw
  // PathNotFoundException and fail the whole import.
  testWidgets(
    'iOS mokuro folder import imports the tapped .html when a page is missing',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final l10n = await loadExpectedL10n();

      // Shaped like real mokuro output: a bracketed Japanese volume name the
      // HTML percent-encodes, one OCR JSON per page, and a page that a sync
      // client never finished downloading (only its partial file exists).
      const stem = '[なもり] ゆるゆり 第15巻-2k';
      final folder = Directory(p.join(tempDir.path, 'yuruyuri'))..createSync();
      final imageDir = Directory(p.join(folder.path, stem))..createSync();
      final ocrDir = Directory(p.join(folder.path, '_ocr', stem))
        ..createSync(recursive: true);
      const pages = ['00_cover.jpg', '15_002.jpg', '15_007.jpg'];
      for (final name in pages) {
        File(
          p.join(ocrDir.path, '${p.basenameWithoutExtension(name)}.json'),
        ).writeAsStringSync('{"img_width": 4, "img_height": 6, "blocks": []}');
      }
      // A real JPEG with a visible colour, so a working cover is not
      // mistaken for a blank tile when watching the run.
      final page = img.Image(width: 60, height: 90);
      img.fill(page, color: img.ColorRgb8(200, 40, 60));
      final jpg = img.encodeJpg(page);
      File(p.join(imageDir.path, '00_cover.jpg')).writeAsBytesSync(jpg);
      File(p.join(imageDir.path, '15_002.jpg')).writeAsBytesSync(jpg);
      File(
        p.join(imageDir.path, '15_007.jpg.sydownload'),
      ).writeAsBytesSync(const []);
      final encodedDir = Uri.encodeComponent(stem);
      File(p.join(folder.path, '$stem.mobile.html')).writeAsStringSync(
        '<html><head><title>$stem | mokuro</title></head><body>'
        '${pages.map((name) => '<div style="background-image:url(&quot;$encodedDir/$name&quot;)"></div>').join()}'
        '</body></html>',
      );

      const filesChannel = MethodChannel('mekuru/ios_files');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        filesChannel,
        (call) async => call.method == 'pickFolder' ? folder.path : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(filesChannel, null));

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text(l10n.libraryImportManga));
      await tester.tap(find.text(l10n.libraryImportManga));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tapSheetItem(tester, l10n.libraryImportMokuroFolder);
      await pumpUntilVisible(tester, find.text('$stem.mobile.html'));
      await tapSheetItem(tester, '$stem.mobile.html');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );
      for (var i = 0; i < 80; i++) {
        if (!container.read(bookImportProvider).isImporting) break;
        await tester.pump(const Duration(milliseconds: 250));
      }
      final importState = container.read(bookImportProvider);
      expect(importState.error, isNull);
      final book = importState.importedBook!;
      // Cancel the success banner's auto-dismiss timer while the container
      // is alive.
      container.read(bookImportProvider.notifier).clearState();

      expect(book.title, stem);
      expect(book.totalPages, pages.length);
      // The pages live in the app now, not in the session-scoped folder.
      final pagesDir = p.join(book.filePath, 'pages');
      expect(p.isWithin((await appBooksDir()).path, pagesDir), isTrue);
      expect(book.coverImagePath, p.join(pagesDir, '00_cover.jpg'));
      expect(File(p.join(pagesDir, '15_002.jpg')).existsSync(), isTrue);
      expect(File(p.join(pagesDir, '15_007.jpg')).existsSync(), isFalse);

      // The tile draws the copied cover: decoded, not the placeholder.
      final tileCover = find.byType(BookCoverImage);
      await pumpUntilVisible(
        tester,
        find.descendant(
          of: tileCover,
          matching: find.byWidgetPredicate(
            (w) => w is RawImage && w.image != null,
          ),
        ),
      );
      expect(
        find.descendant(of: tileCover, matching: find.byIcon(Icons.menu_book)),
        findsNothing,
      );
    },
    skip: !Platform.isIOS,
  );
}
