import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_database.dart';

/// The per-book "Shift pairs by one page" choice: saved on the book and
/// carried by the light backup.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool?> shiftOf(int bookId) async => (await (db.select(
    db.books,
  )..where((t) => t.id.equals(bookId))).getSingle()).mangaSpreadShift;

  test('the repository saves and clears it', () async {
    final id = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: '漫画', filePath: '/books/m'));
    expect(await shiftOf(id), isNull);

    await BookRepository(db).updateMangaSpreadShift(id, true);
    expect(await shiftOf(id), isTrue);
    await BookRepository(db).updateMangaSpreadShift(id, false);
    expect(await shiftOf(id), isFalse);
  });

  test('survives backup, serialize, restore', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '漫画',
            filePath: '/books/m',
            mangaSpreadShift: const Value(true),
          ),
        );

    final manifest = await BackupService(db, BookMatchService()).createBackup();
    expect(manifest.books.single.mangaSpreadShift, isTrue);
    final decoded = BackupSerializer.decode(BackupSerializer.encode(manifest));
    expect(decoded.books.single.mangaSpreadShift, isTrue);

    final targetId = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: '漫画2', filePath: '/books/m2'));
    await RestoreService(
      db,
      BookMatchService(),
      PendingBookDataRepository(db),
    ).applyBookData(targetId, decoded.books.single);
    expect(await shiftOf(targetId), isTrue);
  });

  test(
    'a backup made before the setting existed restores it as null',
    () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: '漫画',
              filePath: '/books/m',
              mangaSpreadShift: const Value(true),
            ),
          );
      final json =
          jsonDecode(
                BackupSerializer.encode(
                  await BackupService(db, BookMatchService()).createBackup(),
                ),
              )
              as Map<String, dynamic>;
      ((json['books'] as List).single as Map).remove('mangaSpreadShift');

      final decoded = BackupSerializer.decode(jsonEncode(json));
      expect(decoded.books.single.mangaSpreadShift, isNull);
    },
  );
}
