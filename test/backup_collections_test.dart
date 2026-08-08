import 'package:drift/native.dart';
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

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late CollectionRepository collections;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    collections = CollectionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook(String title) => db
      .into(db.books)
      .insert(BooksCompanion.insert(title: title, filePath: '/books/$title'));

  test(
    'createBackup includes per-book and manifest collection names',
    () async {
      final bookId = await insertBook('猫');
      final shelfId = await collections.createCollection('Shelf');
      await collections.createCollection('Empty');
      await collections.setBookCollections(bookId, {shelfId});

      final manifest = await BackupService(
        db,
        BookMatchService(),
      ).createBackup();

      expect(manifest.collections.toSet(), {'Shelf', 'Empty'});
      expect(manifest.books.single.collections, ['Shelf']);
    },
  );

  test('serializer round-trips collections', () {
    final manifest = BackupManifest(
      version: 1,
      createdAt: DateTime.utc(2026, 3, 5),
      settings: const BackupSettings(app: {}, reader: {}),
      savedWords: const [],
      books: const [
        BackupBookEntry(
          bookKey: 'k',
          title: 'T',
          bookType: 'epub',
          readProgress: 0.0,
          bookmarks: [],
          highlights: [],
          collections: ['Shelf', 'Novels'],
        ),
      ],
      collections: const ['Shelf', 'Novels', 'Empty'],
    );

    final decoded = BackupSerializer.decode(BackupSerializer.encode(manifest));

    expect(decoded.collections, ['Shelf', 'Novels', 'Empty']);
    expect(decoded.books.single.collections, ['Shelf', 'Novels']);
  });

  test(
    'applyBookData recreates collections and memberships idempotently',
    () async {
      final bookId = await insertBook('猫');
      final restore = RestoreService(
        db,
        BookMatchService(),
        PendingBookDataRepository(db),
      );
      const entry = BackupBookEntry(
        bookKey: 'k',
        title: '猫',
        bookType: 'epub',
        readProgress: 0.5,
        bookmarks: [],
        highlights: [],
        collections: ['Shelf'],
      );

      await restore.applyBookData(bookId, entry);
      await restore.applyBookData(bookId, entry);

      final all = await collections.watchCollections().first;
      expect(all.map((c) => c.name), ['Shelf']);
      final memberships = await collections.watchMemberships().first;
      expect(memberships.single.bookId, bookId);
      expect(memberships.single.collectionId, all.single.id);
    },
  );

  test(
    'restoreBooks creates manifest-level collections without duplicates',
    () async {
      await collections.createCollection('Existing');
      final restore = RestoreService(
        db,
        BookMatchService(),
        PendingBookDataRepository(db),
      );
      final manifest = BackupManifest(
        version: 1,
        createdAt: DateTime.utc(2026, 3, 5),
        settings: const BackupSettings(app: {}, reader: {}),
        savedWords: const [],
        books: const [],
        collections: const ['Existing', 'Empty'],
      );

      await restore.restoreBooks(manifest);

      final all = await collections.watchCollections().first;
      expect(all.map((c) => c.name), ['Empty', 'Existing']);
    },
  );
}
