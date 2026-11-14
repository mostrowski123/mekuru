import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_database.dart';

void main() {
  late AppDatabase db;
  late CollectionRepository collections;
  late RestoreService restore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    collections = CollectionRepository(db);
    restore = RestoreService(
      db,
      BookMatchService(),
      PendingBookDataRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook(String title, {bool favorite = false}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: title,
          filePath: '/books/$title',
          isFavorite: Value(favorite),
        ),
      );

  Future<bool> bookIsFavorite(int id) async => (await (db.select(
    db.books,
  )..where((t) => t.id.equals(id))).getSingle()).isFavorite;

  Future<Set<String>> favoriteFolders() async => {
    for (final c in await db.select(db.collections).get())
      if (c.isFavorite) c.name,
  };

  BackupBookEntry entry({bool? favorite}) => BackupBookEntry(
    bookKey: 'k',
    title: 'T',
    bookType: 'epub',
    readProgress: 0.0,
    bookmarks: const [],
    highlights: const [],
    favorite: favorite,
  );

  BackupManifest manifest({
    List<BackupBookEntry> books = const [],
    List<String> collections = const [],
    List<String> favoriteCollections = const [],
  }) => BackupManifest(
    version: 1,
    createdAt: DateTime.utc(2026, 11, 14),
    settings: const BackupSettings(app: {}, reader: {}),
    savedWords: const [],
    books: books,
    collections: collections,
    favoriteCollections: favoriteCollections,
  );

  test('createBackup records favorite books and folders', () async {
    await insertBook('Starred', favorite: true);
    await insertBook('Plain');
    final series = await collections.createCollection('Series');
    await collections.createCollection('Other');
    await collections.setFavorite(series, true);

    final backup = await BackupService(db, BookMatchService()).createBackup();

    expect(backup.favoriteCollections, ['Series']);
    expect(
      {for (final b in backup.books) b.title: b.favorite},
      {'Starred': true, 'Plain': false},
    );
  });

  test('favorites survive encode and decode', () {
    final decoded = BackupSerializer.decode(
      BackupSerializer.encode(
        manifest(
          books: [entry(favorite: true)],
          collections: const ['Series', 'Other'],
          favoriteCollections: const ['Series'],
        ),
      ),
    );

    expect(decoded.favoriteCollections, ['Series']);
    expect(decoded.books.single.favorite, isTrue);
  });

  test('a book waiting for its import keeps its favorite flag', () {
    // A book that is not in the library yet is stored as one encoded entry
    // and applied when it is imported.
    final decoded = BackupSerializer.decodeBookEntry(
      BackupSerializer.encodeBookEntry(entry(favorite: true)),
    );

    expect(decoded.favorite, isTrue);
  });

  test('a backup from before favorites decodes with none', () {
    const json =
        '{"version":1,"appName":"mekuru","createdAt":"2026-03-05T00:00:00.000Z",'
        '"settings":{"app":{},"reader":{}},"dictionaryPreferences":[],'
        '"savedWords":[],"collections":["Series"],'
        '"books":[{"bookKey":"k","title":"T","bookType":"epub",'
        '"readProgress":0.0,"bookmarks":[],"highlights":[]}]}';

    final decoded = BackupSerializer.decode(json);

    expect(decoded.favoriteCollections, isEmpty);
    expect(decoded.books.single.favorite, isNull);
  });

  test('restoreBooks marks favorite folders, creating missing ones', () async {
    await collections.createCollection('Existing');

    await restore.restoreBooks(
      manifest(
        collections: const ['Existing', 'New', 'Plain'],
        favoriteCollections: const ['Existing', 'New'],
      ),
    );

    expect(await favoriteFolders(), {'Existing', 'New'});
    final all = await db.select(db.collections).get();
    expect(all.map((c) => c.name).toSet(), {'Existing', 'New', 'Plain'});
  });

  test('applyBookData sets and clears the favorite flag', () async {
    final id = await insertBook('Book');

    await restore.applyBookData(id, entry(favorite: true));
    expect(await bookIsFavorite(id), isTrue);

    await restore.applyBookData(id, entry(favorite: false));
    expect(await bookIsFavorite(id), isFalse);
  });

  test('a backup from before favorites clears no favorite', () async {
    final id = await insertBook('Book', favorite: true);
    final series = await collections.createCollection('Series');
    await collections.setFavorite(series, true);

    await restore.restoreBooks(manifest(collections: const ['Series']));
    await restore.applyBookData(id, entry());

    expect(await bookIsFavorite(id), isTrue);
    expect(await favoriteFolders(), {'Series'});
  });
}
