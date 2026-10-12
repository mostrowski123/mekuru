// Spread view pairs pages the way the book says (issue #37): ComicInfo
// double pages and wide pages stand alone, "Shift pairs by one page" stays
// with the book, and the last spread finishes it. A converted EPUB's
// spreads reach an exported CBZ's ComicInfo.xml. No WebView.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/comic_info.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:path/path.dart' as p;

import '../test/shared/epub_fixtures.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('manga_spread_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  /// Eight portrait pages, except page 5 (0-based), which is wide; the
  /// ComicInfo.xml marks page 2 as a double page and the book right to left.
  Future<Book> importComic(AppDatabase db) async {
    final archive = Archive();
    void add(String name, List<int> bytes) =>
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
    for (var i = 0; i < 8; i++) {
      add(
        '${i + 1}.png',
        img.encodePng(
          i == 5
              ? img.Image(width: 300, height: 200)
              : img.Image(width: 200, height: 300),
        ),
      );
    }
    add(
      'ComicInfo.xml',
      utf8.encode(
        '<ComicInfo><Series>見開きテスト</Series>'
        '<Manga>YesAndRightToLeft</Manga>'
        '<Pages><Page Image="2" DoublePage="True"/></Pages></ComicInfo>',
      ),
    );
    final path = p.join(tempDir.path, 'spreads.cbz');
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    return (await BookRepository(db).importCbz(path)).book;
  }

  Future<void> openReader(
    WidgetTester tester,
    AppDatabase db,
    Book book,
  ) async {
    final settings = InMemoryReaderSettingsStorage();
    await settings.save(
      const ReaderSettings(mangaViewMode: MangaViewMode.twoPageSpread),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
        readerSettingsStorage: settings,
      ),
    );
    await pumpUntilVisible(tester, find.byType(MangaSpreadView));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Each spread's pages in reading order (this book reads right to left).
  List<List<int>> spreads(WidgetTester tester) => [
    for (final s
        in tester.widget<MangaSpreadView>(find.byType(MangaSpreadView)).spreads)
      [?s.rightPageIndex, ?s.leftPageIndex],
  ];

  Future<Book> reload(AppDatabase db, Book book) async =>
      (await BookRepository(db).getBookById(book.id))!;

  testWidgets(
    'double and wide pages stand alone; a shift stays with the book',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final l10n = await loadExpectedL10n();
      final book = await importComic(db);
      expect(book.title, '見開きテスト');
      expect(book.pageProgressionDirection, 'rtl');

      await openReader(tester, db, book);
      expect(spreads(tester), [
        [0],
        [1],
        [2],
        [3, 4],
        [5],
        [6, 7],
      ]);

      // Settings sheet → This book → Shift pairs by one page.
      await tester.tapAt(tester.getCenter(find.byType(MangaReaderScreen)));
      await pumpUntilVisible(tester, find.byIcon(Icons.settings));
      await tester.tap(find.byIcon(Icons.settings));
      await pumpUntilVisible(tester, find.byType(BottomSheet));
      final shift = find.text(l10n.mangaShiftSpreadsTitle);
      await tester.scrollUntilVisible(
        shift,
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(shift);
      await tester.pump(const Duration(milliseconds: 500));

      const shifted = [
        [0, 1],
        [2],
        [3],
        [4],
        [5],
        [6],
        [7],
      ];
      expect(spreads(tester), shifted);
      expect((await reload(db, book)).mangaSpreadShift, isTrue);

      // Reopened, the book keeps its shift.
      await tester.pumpWidget(const SizedBox());
      await openReader(tester, db, await reload(db, book));
      expect(spreads(tester), shifted);
    },
  );

  testWidgets('the last spread finishes the book', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final book = await importComic(db);
    await openReader(tester, db, book);

    // The last spread shows pages 6 and 7.
    tester
        .state<MangaSpreadViewState>(find.byType(MangaSpreadView))
        .goToSpread(5, animate: false);
    await tester.pump(const Duration(milliseconds: 500));

    final read = await reload(db, book);
    expect(read.lastReadCfi, '6');
    expect(read.readProgress, 1.0);
  });

  testWidgets('a converted EPUB exports its spreads in ComicInfo.xml', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);
    final epubPath = await createFixedLayoutMangaEpub(
      pageCount: 4,
      itemrefProperties: {1: 'rendition:page-spread-center'},
      landscapePages: {3},
    );
    addTearDown(() => File(epubPath).parent.delete(recursive: true));
    final book = await repo.convertEpubToManga(await repo.importEpub(epubPath));

    final (cbzPath, _) = await repo.exportMangaCbz(
      book,
      fileName: 'spreads.cbz',
      rtl: true,
    );
    addTearDown(() => File(cbzPath).delete());

    final archive = ZipDecoder().decodeBytes(await File(cbzPath).readAsBytes());
    final info = ComicInfo.tryParse(
      utf8.decode(archive.findFile('ComicInfo.xml')!.content),
    )!;
    expect(info.title, book.title);
    expect(info.direction, 'rtl');
    expect(info.doublePages, {1, 3});
  });
}
