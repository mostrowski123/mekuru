import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('per-book furigana mode survives backup, serialize, restore', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '猫',
            filePath: '/books/neko',
            furiganaMode: const Value('aboveLevel'),
          ),
        );

    final manifest = await BackupService(db, BookMatchService()).createBackup();
    expect(manifest.books.single.furiganaMode, 'aboveLevel');

    final decoded = BackupSerializer.decode(BackupSerializer.encode(manifest));
    expect(decoded.books.single.furiganaMode, 'aboveLevel');

    final targetId = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: '猫2', filePath: '/books/neko2'));
    final restore = RestoreService(
      db,
      BookMatchService(),
      PendingBookDataRepository(db),
    );
    await restore.applyBookData(targetId, decoded.books.single);

    final restored = await (db.select(
      db.books,
    )..where((t) => t.id.equals(targetId))).getSingle();
    expect(restored.furiganaMode, 'aboveLevel');
  });

  test('books without an override round-trip as null', () async {
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: '犬', filePath: '/books/inu'));

    final manifest = await BackupService(db, BookMatchService()).createBackup();
    final decoded = BackupSerializer.decode(BackupSerializer.encode(manifest));

    expect(decoded.books.single.furiganaMode, isNull);
  });
}
