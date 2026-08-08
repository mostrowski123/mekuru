import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late CollectionRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = CollectionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook(String title) => db
      .into(db.books)
      .insert(BooksCompanion.insert(title: title, filePath: '/books/$title'));

  test(
    'createCollection returns id and watchCollections orders by name',
    () async {
      final novels = await repo.createCollection('Novels');
      final manga = await repo.createCollection('Manga');

      final collections = await repo.watchCollections().first;

      expect(collections.map((c) => c.name), ['Manga', 'Novels']);
      expect(collections.map((c) => c.id), [manga, novels]);
    },
  );

  test('renameCollection updates the name', () async {
    final id = await repo.createCollection('Nvoels');
    await repo.renameCollection(id, 'Novels');

    final collections = await repo.watchCollections().first;
    expect(collections.single.name, 'Novels');
  });

  test('setBookCollections replaces memberships', () async {
    final bookId = await insertBook('猫');
    final a = await repo.createCollection('A');
    final b = await repo.createCollection('B');

    await repo.setBookCollections(bookId, {a, b});
    var memberships = await repo.watchMemberships().first;
    expect(memberships.map((m) => m.collectionId).toSet(), {a, b});
    expect(memberships.every((m) => m.bookId == bookId), isTrue);

    await repo.setBookCollections(bookId, {b});
    memberships = await repo.watchMemberships().first;
    expect(memberships.single.collectionId, b);
  });

  test('deleteCollection removes memberships but keeps books', () async {
    final bookId = await insertBook('猫');
    final id = await repo.createCollection('A');
    await repo.setBookCollections(bookId, {id});

    await repo.deleteCollection(id);

    expect(await repo.watchCollections().first, isEmpty);
    expect(await repo.watchMemberships().first, isEmpty);
    expect(await db.select(db.books).get(), hasLength(1));
  });

  Future<Map<int, int>> positionsIn(int collectionId) async {
    final rows = await db.select(db.bookCollections).get();
    return {
      for (final m in rows)
        if (m.collectionId == collectionId) m.bookId: m.position,
    };
  }

  test(
    'setBookCollections preserves positions of retained memberships',
    () async {
      final a = await insertBook('猫');
      final b = await insertBook('犬');
      final shelf = await repo.createCollection('Shelf');
      final other = await repo.createCollection('Other');
      await repo.addBooksToCollection(shelf, {a, b});
      await repo.reorderCollectionBooks(shelf, [b, a]); // a now at position 1

      // Toggling an unrelated collection on must not touch the Shelf row.
      await repo.setBookCollections(a, {shelf, other});

      expect((await positionsIn(shelf))[a], 1);
    },
  );

  test('setBookCollections appends new memberships at the end', () async {
    final a = await insertBook('猫');
    final b = await insertBook('犬');
    final shelf = await repo.createCollection('Shelf');
    await repo.addBooksToCollection(shelf, {a});
    await repo.reorderCollectionBooks(shelf, [a]); // a at 0

    await repo.setBookCollections(b, {shelf});

    final positions = await positionsIn(shelf);
    expect(positions[b], greaterThan(positions[a]!));
  });

  test('reorderCollectionBooks writes dense 0..n-1', () async {
    final a = await insertBook('猫');
    final b = await insertBook('犬');
    final c = await insertBook('鳥');
    final shelf = await repo.createCollection('Shelf');
    await repo.addBooksToCollection(shelf, {a, b, c});

    await repo.reorderCollectionBooks(shelf, [c, a, b]);

    expect(await positionsIn(shelf), {c: 0, a: 1, b: 2});
  });

  test('addBooksToCollection appends and is idempotent', () async {
    final a = await insertBook('猫');
    final b = await insertBook('犬');
    final shelf = await repo.createCollection('Shelf');
    await repo.addBooksToCollection(shelf, {a});
    await repo.reorderCollectionBooks(shelf, [a]);

    await repo.addBooksToCollection(shelf, {a, b});
    await repo.addBooksToCollection(shelf, {a, b});

    final positions = await positionsIn(shelf);
    expect(positions.keys.toSet(), {a, b});
    expect(positions[a], 0); // untouched by the re-add
    expect(positions[b], greaterThan(0));
  });

  test('removeBooksFromCollection deletes only the named pairs', () async {
    final a = await insertBook('猫');
    final b = await insertBook('犬');
    final shelf = await repo.createCollection('Shelf');
    final other = await repo.createCollection('Other');
    await repo.addBooksToCollection(shelf, {a, b});
    await repo.addBooksToCollection(other, {a});

    await repo.removeBooksFromCollection(shelf, {a});

    expect((await positionsIn(shelf)).keys.toSet(), {b});
    expect((await positionsIn(other)).keys.toSet(), {a});
  });

  group('booksInCollectionOrder', () {
    Book makeBook(int id) => Book(
      id: id,
      title: 'Book $id',
      filePath: '/books/$id',
      bookType: 'epub',
      totalPages: 0,
      readProgress: 0.0,
      dateAdded: DateTime(2026, 1, 1),
    );

    BookCollection member(int bookId, int collectionId, int position) =>
        BookCollection(
          bookId: bookId,
          collectionId: collectionId,
          position: position,
        );

    test('orders members by position and excludes non-members', () {
      final books = [makeBook(1), makeBook(2), makeBook(3)];
      final result = booksInCollectionOrder(
        collectionId: 7,
        books: books,
        memberships: [member(1, 7, 2), member(3, 7, 0), member(2, 99, 0)],
      );
      expect(result.map((b) => b.id), [3, 1]);
    });

    test('all-zero positions fall back to the incoming (library) order', () {
      final books = [makeBook(5), makeBook(2), makeBook(9)];
      final result = booksInCollectionOrder(
        collectionId: 7,
        books: books,
        memberships: [member(9, 7, 0), member(5, 7, 0), member(2, 7, 0)],
      );
      expect(result.map((b) => b.id), [5, 2, 9]);
    });
  });

  test('deleteBook removes its memberships', () async {
    final bookRepo = BookRepository(db);
    final bookId = await insertBook('猫');
    final keep = await insertBook('犬');
    final id = await repo.createCollection('A');
    await repo.setBookCollections(bookId, {id});
    await repo.setBookCollections(keep, {id});

    await bookRepo.deleteBook(bookId);

    final memberships = await repo.watchMemberships().first;
    expect(memberships.single.bookId, keep);
  });
}
