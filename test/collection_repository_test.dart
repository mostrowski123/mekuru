import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';

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
