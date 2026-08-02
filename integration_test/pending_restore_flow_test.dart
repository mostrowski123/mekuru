import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_infrastructure.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'pending book data reattaches when matching book is later imported',
    () async {
      final sourceDb = createTestDatabase();
      addTearDown(sourceDb.close);

      final sourceBookId = await sourceDb
          .into(sourceDb.books)
          .insert(
            BooksCompanion.insert(
              title: 'Pending Book',
              filePath: '/fake/pending.epub',
              readProgress: const Value(0.75),
              lastReadCfi: const Value('epubcfi(/6/12!/4)'),
            ),
          );
      await sourceDb
          .into(sourceDb.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              bookId: sourceBookId,
              cfi: 'epubcfi(/6/4)',
              chapterTitle: const Value('Pending chapter'),
            ),
          );

      final manifest = await BackupService(
        sourceDb,
        BookMatchService(),
      ).createBackup();

      // Target DB has no matching book yet, so restoreBooks must enqueue.
      final targetDb = createTestDatabase();
      addTearDown(targetDb.close);
      final pendingRepo = PendingBookDataRepository(targetDb);
      final restoreService = RestoreService(
        targetDb,
        BookMatchService(),
        pendingRepo,
      );

      final queued = await restoreService.restoreBooks(manifest);
      expect(queued.applied, 0);
      expect(queued.pending, 1);
      expect(await pendingRepo.getAll(), hasLength(1));

      // Simulate the user importing the matching book later. The library
      // import flow's reattach logic (lib/features/library/presentation/
      // providers/library_providers.dart `_applyPendingDataIfExists`) is
      // replicated here verbatim — it is private but is the contract being
      // verified.
      final newBookId = await targetDb
          .into(targetDb.books)
          .insert(
            BooksCompanion.insert(
              title: 'Pending Book',
              filePath: '/fake/pending.epub',
            ),
          );

      final matchService = BookMatchService();
      final key = await matchService.generatePreferredKey(
        'Pending Book',
        'epub',
        '/fake/pending.epub',
      );
      final pending = await pendingRepo.findByBookKey(key);
      expect(pending, isNotNull);

      final entry = BackupSerializer.decodeBookEntry(pending!.dataJson);
      await restoreService.applyBookData(newBookId, entry);
      await pendingRepo.deleteById(pending.id);

      final book = await (targetDb.select(
        targetDb.books,
      )..where((t) => t.id.equals(newBookId))).getSingle();
      expect(book.readProgress, 0.75);
      expect(book.lastReadCfi, 'epubcfi(/6/12!/4)');

      final bookmarks = await (targetDb.select(
        targetDb.bookmarks,
      )..where((t) => t.bookId.equals(newBookId))).get();
      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.cfi, 'epubcfi(/6/4)');
      expect(bookmarks.single.chapterTitle, 'Pending chapter');

      expect(await pendingRepo.getAll(), isEmpty);
    },
  );

  test(
    'PendingBookDataRepository.insert keeps only the latest entry per key',
    () async {
      // Prevents accumulating duplicate pending rows if a user restores the
      // same backup multiple times before re-importing the book.
      final db = createTestDatabase();
      addTearDown(db.close);

      final repo = PendingBookDataRepository(db);
      await repo.insert('epub::test', '{"v":1}');
      await repo.insert('epub::test', '{"v":2}');

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.single.dataJson, '{"v":2}');
    },
  );

  test(
    'queued dictionary preferences apply order and enabled state when matching dictionaries exist',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final dictRepo = DictionaryRepository(db);

      await db
          .into(db.dictionaryMetas)
          .insert(
            DictionaryMetasCompanion.insert(
              name: 'Dict A',
              sortOrder: const Value(0),
            ),
          );
      await db
          .into(db.dictionaryMetas)
          .insert(
            DictionaryMetasCompanion.insert(
              name: 'Dict B',
              sortOrder: const Value(1),
            ),
          );
      await db
          .into(db.dictionaryMetas)
          .insert(
            DictionaryMetasCompanion.insert(
              name: 'Dict C',
              sortOrder: const Value(2),
            ),
          );

      final service = PendingDictionaryRestoreService();
      final queueResult = await service.queueFromBackup(
        preferences: const [
          BackupDictionaryPreference(
            name: 'Dict B',
            sortOrder: 0,
            isEnabled: false,
          ),
          BackupDictionaryPreference(
            name: 'Dict A',
            sortOrder: 1,
            isEnabled: true,
          ),
          // Dict X is in the backup but not installed locally; it must be
          // reported as missing, not silently dropped.
          BackupDictionaryPreference(
            name: 'Dict X',
            sortOrder: 2,
            isEnabled: true,
          ),
        ],
        shouldQueue: true,
        repository: dictRepo,
      );
      expect(queueResult.queued, isTrue);
      expect(queueResult.totalCount, 3);
      expect(await service.loadPendingRestore(), isNotNull);

      final applyResult = await service.applyPendingRestore(dictRepo);
      expect(applyResult.appliedCount, 2);
      expect(applyResult.missingCount, 1);

      final all = await dictRepo.getAllDictionaries();
      final visible = all.where((d) => !d.isHidden).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(visible.map((d) => d.name).toList(), [
        'Dict B',
        'Dict A',
        'Dict C',
      ]);
      expect(visible.firstWhere((d) => d.name == 'Dict B').isEnabled, isFalse);
      expect(visible.firstWhere((d) => d.name == 'Dict A').isEnabled, isTrue);

      // Snapshot must clear after successful apply, otherwise it would
      // re-apply on every subsequent dictionary import.
      expect(await service.loadPendingRestore(), isNull);
    },
  );
}
