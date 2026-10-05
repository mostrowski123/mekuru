import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/main.dart' show navigatorKey;
import 'package:path/path.dart' as p;

import 'shared/pdf_fixtures.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// PDF import on device: PDFium renders the pages and reads the text layer
/// of the generated fixtures (tools/make_pdf_fixtures.py), the glyphs become
/// tappable blocks, scanned PDFs explain themselves, and PDF books turn
/// their own way while other manga keep the global direction.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_import_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  Future<String> writeFixture(String name, String base64) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(base64Decode(base64));
    return path;
  }

  Future<MokuroBook> pagesOf(Book book) =>
      MangaCacheStore.read(p.join(book.filePath, mangaPagesCacheFileName));

  String textOf(MokuroPage page) =>
      page.blocks.map((block) => block.lines.join()).join();

  Future<void> openReader(
    WidgetTester tester,
    AppDatabase db,
    Book book,
  ) async {
    // The global manga direction is left to right.
    final settings = InMemoryReaderSettingsStorage();
    await settings.save(
      const ReaderSettings(mangaReadingDirection: ReaderDirection.ltr),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
        readerSettingsStorage: settings,
      ),
    );
    await pumpUntilVisible(tester, find.byType(PageView));
    await tester.pump(const Duration(milliseconds: 500));
  }

  bool readsRightToLeft(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).reverse;

  testWidgets('a text PDF imports as pages with tappable Japanese words', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final path = await writeFixture('graded_reader.pdf', textPdfBase64);
    final pdf = await BookRepository(db).importPdf(path);

    expect(pdf.scanned, isFalse);
    expect(pdf.book.title, 'graded_reader');
    expect(pdf.book.bookType, 'manga');
    expect(pdf.book.totalPages, 2);
    // One vertical page of two: a tie turns right to left.
    expect(pdf.book.pageProgressionDirection, 'rtl');
    expect(File(path).existsSync(), isTrue, reason: 'caller keeps the PDF');

    final manga = await pagesOf(pdf.book);
    expect(manga.fromPdf, isTrue);
    expect(manga.ocrSource, 'pdf');
    expect(manga.ocrCompleted, isTrue);
    final [horizontal, vertical] = manga.pages;
    expect(horizontal.blocks.every((block) => !block.vertical), isTrue);
    expect(vertical.blocks.every((block) => block.vertical), isTrue);
    for (final page in manga.pages) {
      expect(textOf(page), contains('今日は学校で日本語を勉強します。'));
      // Furigana is drawn beside the text, never looked up.
      expect(textOf(page), isNot(contains('きょう')));
      expect(page.blocks.expand((block) => block.words), isNotEmpty);
      expect(
        File(p.join(manga.imageDirPath, page.imageFileName)).existsSync(),
        isTrue,
      );
    }
  });

  testWidgets('a scanned PDF tells the user why its words are not tappable', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    final db = createTestDatabase();
    addTearDown(db.close);
    final path = await writeFixture('scan.pdf', scannedPdfBase64);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const LibraryScreen(),
        navigatorKey: navigatorKey,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );

    final imported = await container
        .read(bookImportProvider.notifier)
        .importFiles([path], format: 'pdf');
    expect(imported, 1);

    await pumpUntilVisible(tester, find.text(l10n.pdfScannedTitle));
    expect(find.text(l10n.ocrRunActionTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonOk));
    await pumpUntilGone(tester, find.text(l10n.pdfScannedTitle));

    final book = (await db.select(db.books).get()).single;
    // Nothing tells the direction: it follows the reader's setting.
    expect(book.pageProgressionDirection, isNull);
    final manga = await pagesOf(book);
    expect(manga.fromPdf, isTrue);
    expect(manga.ocrCompleted, isFalse, reason: 'OCR can still fill it');
    expect(manga.pages.expand((page) => page.blocks), isEmpty);

    container.read(bookImportProvider.notifier).clearState();
    await tester.pump();
  });

  testWidgets('a phrase-spaced line that starts beyond the BMP reads right', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final path = await writeFixture('phrases.pdf', phrasePdfBase64);

    final book = (await BookRepository(db).importPdf(path)).book;
    final page = (await pagesOf(book)).pages.single;

    // 𠮟 is two UTF-16 units, and PDFium reports a character box for each:
    // the text and the boxes stay paired, so no character after it lands on
    // its neighbour's box. And each phrase gets a box of its own, so taps
    // after a phrase space land on what is drawn there.
    final block = page.blocks.single;
    expect(block.lines, ['𠮟られた', 'ねこが', 'にげました。']);
    final points = page.imgWidth / 420; // pixels per point on the A5 page
    expect(
      [for (final quad in block.linesCoords) quad.first.first / points],
      [closeTo(30, 3), closeTo(130, 3), closeTo(210, 3)],
    );
  });

  testWidgets('Delete OCR on a PDF brings its own text back', (tester) async {
    final l10n = await loadExpectedL10n();
    final db = createTestDatabase();
    addTearDown(db.close);
    final path = await writeFixture('graded_reader.pdf', textPdfBase64);
    final book = (await BookRepository(db).importPdf(path)).book;
    final imported = await pagesOf(book);

    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const LibraryScreen()),
    );
    final tile = find.byKey(ValueKey('book-tile-${book.id}'));
    await pumpUntilVisible(tester, tile);

    // The PDF's own text is no OCR: there is nothing to delete.
    await longPressTile(tester, tile);
    expect(find.text(l10n.localOcrRecognize), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // the sheet's file check
    expect(find.text(l10n.ocrRemoveActionTitle), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 400));

    // An OCR run replaces the text.
    await MangaCacheStore.reset(
      File(p.join(book.filePath, mangaPagesCacheFileName)),
      book.id,
      jsonEncode(
        imported
            .copyWith(
              ocrSource: 'local',
              pages: [
                for (final page in imported.pages)
                  page.copyWith(blocks: const []),
              ],
            )
            .toJson(),
      ),
    );

    await longPressTile(tester, tile);
    await pumpUntilVisible(tester, find.text(l10n.ocrRemovePdfSubtitle));
    await tapSheetItem(tester, l10n.ocrRemoveActionTitle);
    expect(find.text(l10n.ocrRemovePdfBody), findsOneWidget);
    await tester.tap(
      find.widgetWithText(TextButton, l10n.ocrRemoveActionTitle),
    );
    await pumpUntilVisible(tester, find.text(l10n.ocrRemovedFromBook));

    final restored = await pagesOf(book);
    expect(restored.ocrSource, 'pdf');
    expect(restored.fromPdf, isTrue);
    for (final page in restored.pages) {
      expect(textOf(page), contains('今日は学校で日本語を勉強します。'));
    }
  });

  testWidgets('a PDF book turns its own way and remembers a new pick', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    final db = createTestDatabase();
    addTearDown(db.close);
    final path = await writeFixture('graded_reader.pdf', textPdfBase64);
    final book = (await BookRepository(db).importPdf(path)).book;

    await openReader(tester, db, book);
    expect(readsRightToLeft(tester), isTrue, reason: 'its own, not global');

    // Settings sheet: the direction row is this book's.
    await tester.tapAt(tester.getCenter(find.byType(MangaReaderScreen)));
    await pumpUntilVisible(tester, find.byIcon(Icons.settings));
    await tester.tap(find.byIcon(Icons.settings));
    await pumpUntilVisible(tester, find.text(l10n.readerReadingDirectionLtr));
    await tester.ensureVisible(find.text(l10n.readerReadingDirectionLtr));
    await tester.tap(find.text(l10n.readerReadingDirectionLtr));
    await tester.pump(const Duration(milliseconds: 500));

    expect(readsRightToLeft(tester), isFalse);
    final row = await (db.select(
      db.books,
    )..where((t) => t.id.equals(book.id))).getSingle();
    expect(row.overrideReadingDirection, 'ltr');
  });

  testWidgets('other manga keep the global direction', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final page = img.encodePng(img.Image(width: 300, height: 500));
    final archive = Archive();
    for (final name in ['0001.png', '0002.png']) {
      archive.addFile(ArchiveFile(name, page.length, page));
    }
    final cbz = p.join(tempDir.path, 'converted.cbz');
    await File(cbz).writeAsBytes(ZipEncoder().encode(archive));
    final repository = BookRepository(db);
    final imported = await repository.importCbz(cbz);
    // An EPUB converted to manga keeps its EPUB's direction on the row.
    await (db.update(db.books)..where((t) => t.id.equals(imported.id))).write(
      const BooksCompanion(pageProgressionDirection: Value('rtl')),
    );
    final book = (await repository.getBookById(imported.id))!;

    await openReader(tester, db, book);

    expect(readsRightToLeft(tester), isFalse);
  });
}
