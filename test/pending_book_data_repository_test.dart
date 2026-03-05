import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late PendingBookDataRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = PendingBookDataRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('PendingBookDataRepository', () {
    test('insert and findByBookKey returns the entry', () async {
      await repo.insert('epub::test book', '{"some":"data"}');

      final result = await repo.findByBookKey('epub::test book');
      expect(result, isNotNull);
      expect(result!.bookKey, 'epub::test book');
      expect(result.dataJson, '{"some":"data"}');
    });

    test('findByBookKey returns null for non-existent key', () async {
      final result = await repo.findByBookKey('epub::missing');
      expect(result, isNull);
    });

    test('getAll returns all entries', () async {
      await repo.insert('epub::book1', '{"a":"1"}');
      await repo.insert('manga::book2', '{"b":"2"}');

      final all = await repo.getAll();
      expect(all, hasLength(2));
    });

    test('deleteById removes the entry', () async {
      await repo.insert('epub::book1', '{"a":"1"}');
      final entry = await repo.findByBookKey('epub::book1');
      expect(entry, isNotNull);

      await repo.deleteById(entry!.id);

      final afterDelete = await repo.findByBookKey('epub::book1');
      expect(afterDelete, isNull);
    });

    test('deleteAll clears the table', () async {
      await repo.insert('epub::book1', '{"a":"1"}');
      await repo.insert('epub::book2', '{"b":"2"}');

      await repo.deleteAll();

      final all = await repo.getAll();
      expect(all, isEmpty);
    });

    test('multiple pending entries can coexist', () async {
      await repo.insert('epub::book1', '{"a":"1"}');
      await repo.insert('manga::book2', '{"b":"2"}');
      await repo.insert('epub::book3', '{"c":"3"}');

      final all = await repo.getAll();
      expect(all, hasLength(3));

      final epub1 = await repo.findByBookKey('epub::book1');
      final manga2 = await repo.findByBookKey('manga::book2');
      expect(epub1, isNotNull);
      expect(manga2, isNotNull);
    });

    test('insert replaces existing row for the same key', () async {
      await repo.insert('epub::same', '{"version":1}');
      await repo.insert('epub::same', '{"version":2}');

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.single.bookKey, 'epub::same');
      expect(all.single.dataJson, '{"version":2}');
    });

    test(
      'findByBookKey tolerates legacy duplicate keys and returns latest row',
      () async {
        await db
            .into(db.pendingBookDatas)
            .insert(
              PendingBookDatasCompanion.insert(
                bookKey: 'epub::legacy',
                dataJson: '{"version":1}',
              ),
            );
        await db
            .into(db.pendingBookDatas)
            .insert(
              PendingBookDatasCompanion.insert(
                bookKey: 'epub::legacy',
                dataJson: '{"version":2}',
              ),
            );

        final result = await repo.findByBookKey('epub::legacy');
        expect(result, isNotNull);
        expect(result!.dataJson, '{"version":2}');
      },
    );
  });
}
