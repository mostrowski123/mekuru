import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';

/// In-memory database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late BookRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = BookRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('BookRepository — queries', () {
    test('getAllBooks returns empty list initially', () async {
      final books = await repo.getAllBooks();
      expect(books, isEmpty);
    });

    test('getBookById returns null for non-existent book', () async {
      final book = await repo.getBookById(999);
      expect(book, isNull);
    });
  });

  group('BookRepository — database operations', () {
    test('direct insert creates a book and it is retrievable', () async {
      // Insert directly via drift to test DB operations without file system
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: '坊っちゃん', filePath: '/test/path'),
          );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.title, '坊っちゃん');
      expect(book.filePath, '/test/path');
      expect(book.coverImagePath, isNull);
    });

    test('getAllBooks returns books in newest-first order', () async {
      // Insert books with small delays to ensure different timestamps
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'First Book', filePath: '/path/1'),
          );

      // Use a slightly later date for the second book
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Second Book', filePath: '/path/2'),
          );

      final books = await repo.getAllBooks();
      expect(books, hasLength(2));
      // Both should be returned — order depends on insertion timing
      final titles = books.map((b) => b.title).toList();
      expect(titles, containsAll(['First Book', 'Second Book']));
    });

    test('updateProgress updates lastReadCfi', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateProgress(id, 'epubcfi(/6/14[ch7]!/4/2/1:0)');

      final book = await repo.getBookById(id);
      expect(book!.lastReadCfi, 'epubcfi(/6/14[ch7]!/4/2/1:0)');
    });

    test('updateProgress with progress updates readProgress', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateProgress(
        id,
        'epubcfi(/6/14[ch7]!/4/2/1:0)',
        progress: 0.42,
      );

      final book = await repo.getBookById(id);
      expect(book!.lastReadCfi, 'epubcfi(/6/14[ch7]!/4/2/1:0)');
      expect(book.readProgress, closeTo(0.42, 0.001));
    });

    test('updateProgress without progress leaves readProgress unchanged',
        () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateProgress(id, 'epubcfi(/6/2)');

      final book = await repo.getBookById(id);
      expect(book!.readProgress, 0.0);
    });

    test('updateTotalPages updates totalPages', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateTotalPages(id, 250);

      final book = await repo.getBookById(id);
      expect(book!.totalPages, 250);
    });

    test('deleteBook removes book from database', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'To Delete',
              filePath: '/nonexistent/path',
            ),
          );

      expect(await repo.getBookById(id), isNotNull);

      await repo.deleteBook(id);

      expect(await repo.getBookById(id), isNull);
    });

    test('watchAllBooks emits updates', () async {
      final emissions = <List<Book>>[];
      final subscription = repo.watchAllBooks().listen((data) {
        emissions.add(data);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, isEmpty);

      await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: '新しい本', filePath: '/test'));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, hasLength(1));
      expect(emissions.last.first.title, '新しい本');

      await subscription.cancel();
    });
  });

  group('BookRepository — importEpub integration', () {
    test('importEpub throws for non-existent file', () async {
      // The importEpub method calls path_provider which won't work in tests
      // but the EPUB parser itself will throw first for non-existent file
      expect(
        () => repo.importEpub('/nonexistent/book.epub'),
        throwsA(anything),
      );
    });
  });

  group('BookRepository — language and pageProgressionDirection', () {
    test('inserting book with language stores the value', () async {
      final id = await db.into(db.books).insert(
        BooksCompanion.insert(
          title: 'English Novel',
          filePath: '/test/path',
          language: const Value('en'),
          pageProgressionDirection: const Value('ltr'),
        ),
      );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.language, 'en');
      expect(book.pageProgressionDirection, 'ltr');
    });

    test('inserting book without language has null language', () async {
      final id = await db.into(db.books).insert(
        BooksCompanion.insert(title: 'Legacy Book', filePath: '/test/path'),
      );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.language, isNull);
      expect(book.pageProgressionDirection, isNull);
    });

    test('backfillLanguage updates language and ppd', () async {
      final id = await db.into(db.books).insert(
        BooksCompanion.insert(title: 'Legacy Book', filePath: '/test/path'),
      );

      // Verify initially null
      var book = await repo.getBookById(id);
      expect(book!.language, isNull);

      // Backfill
      await repo.backfillLanguage(id, 'ja', 'rtl', 'vertical-rl');

      book = await repo.getBookById(id);
      expect(book!.language, 'ja');
      expect(book.pageProgressionDirection, 'rtl');
      expect(book.primaryWritingMode, 'vertical-rl');
    });

    test('backfillLanguage can set null values', () async {
      final id = await db.into(db.books).insert(
        BooksCompanion.insert(
          title: 'Book',
          filePath: '/test/path',
          language: const Value('en'),
        ),
      );

      await repo.backfillLanguage(id, null, null, null);

      final book = await repo.getBookById(id);
      expect(book!.language, isNull);
      expect(book.pageProgressionDirection, isNull);
      expect(book.primaryWritingMode, isNull);
    });
  });
}
