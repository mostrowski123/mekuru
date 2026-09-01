import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/reader/data/services/reader_progress_persistence.dart';

import 'shared/test_infrastructure.dart';

Future<int> _insertBook(
  AppDatabase db,
  String title, {
  String filePath = '/fake/book.epub',
  String bookType = 'epub',
}) => db
    .into(db.books)
    .insert(
      BooksCompanion.insert(
        title: title,
        filePath: filePath,
        bookType: Value(bookType),
      ),
    );

ReaderProgressPersistence _makePersistence(BookRepository repo, int bookId) =>
    ReaderProgressPersistence(
      debounceDuration: const Duration(milliseconds: 10),
      saveProgress: (cfi, progress, {href, hrefProgression}) =>
          repo.updateProgress(
            bookId,
            cfi,
            progress: progress,
            href: href,
            hrefProgression: hrefProgression,
          ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'EPUB CFI flows through ReaderProgressPersistence into the books table',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final bookRepo = BookRepository(db);
      final bookId = await _insertBook(db, 'EPUB Book');

      final persistence = _makePersistence(bookRepo, bookId);
      addTearDown(persistence.dispose);

      persistence.queueSave('epubcfi(/6/4!/4/2/2)', 0.42);
      await persistence.flush();

      final book = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(book.lastReadCfi, 'epubcfi(/6/4!/4/2/2)');
      expect(book.readProgress, 0.42);
      // lastReadAt must populate so the library can sort by most recently read.
      expect(book.lastReadAt, isNotNull);
    },
  );

  test(
    'Manga scroll:<offset> position uses the same persistence path',
    () async {
      // Manga books store position as 'scroll:<pixels>' rather than a CFI.
      // The persistence wrapper treats it as an opaque string — if a future
      // refactor accidentally adds CFI-specific parsing, this catches it.
      final db = createTestDatabase();
      addTearDown(db.close);

      final bookRepo = BookRepository(db);
      final bookId = await _insertBook(
        db,
        'Manga Volume',
        filePath: '/fake/manga.cbz',
        bookType: 'manga',
      );

      final persistence = _makePersistence(bookRepo, bookId);
      addTearDown(persistence.dispose);

      persistence.queueSave('scroll:12480', 0.18);
      await persistence.flush();

      final book = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(book.lastReadCfi, 'scroll:12480');
      expect(book.readProgress, 0.18);
    },
  );

  test(
    'progress survives a persistence instance teardown (simulates app restart)',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final bookRepo = BookRepository(db);
      final bookId = await _insertBook(db, 'Book');

      final first = _makePersistence(bookRepo, bookId);
      first.queueSave('epubcfi(/6/4)', 0.10);
      await first.dispose();

      // After teardown the saved state must be readable from the DB, and a
      // fresh persistence instance must be able to advance it.
      final reloaded = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(reloaded.lastReadCfi, 'epubcfi(/6/4)');
      expect(reloaded.readProgress, 0.10);

      final second = _makePersistence(bookRepo, bookId);
      addTearDown(second.dispose);
      second.queueSave('epubcfi(/6/8)', 0.55);
      await second.flush();

      final advanced = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(advanced.lastReadCfi, 'epubcfi(/6/8)');
      expect(advanced.readProgress, 0.55);
    },
  );
}
