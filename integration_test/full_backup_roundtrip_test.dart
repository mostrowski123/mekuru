import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/full_backup_it_support.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// The whole full-backup chain on a real device: the live database file and
/// `books/` under app support, the native foreground-service job through the
/// real method channel (file endpoints), an independent reader checking the
/// archive, the staged restore, the boot-time fix-ups and apply, and finally
/// the real app booting on the restored data.
///
/// These tests own the device's live database file and `books/` tree; each
/// one starts by wiping both.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late Directory unidicDir;
  late Directory tempDir;

  Future<void> wipeLiveData() async {
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File(
        p.join(root.path, '${StagedFullRestore.databaseFileName}$suffix'),
      );
      if (await file.exists()) await file.delete();
    }
    if (await unidicDir.exists()) await unidicDir.delete(recursive: true);
  }

  setUp(() async {
    root = await getApplicationSupportDirectory();
    documents = await getApplicationDocumentsDirectory();
    unidicDir = Directory(
      p.join(documents.path, FullBackupManifest.unidicDirName),
    );
    tempDir = await Directory.systemTemp.createTemp('full_backup_it_');
    await wipeLiveData();
  });

  tearDown(() async {
    await wipeLiveData();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
    'export → independent reader check → wipe → inspect → restore job → boot apply → the real app shows the restored library',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app.theme_mode': 'dark',
        'reader.font_size': 22.0,
      });

      // ── The source device: a real import into the live database. ──
      var db = AppDatabase();
      final repo = BookRepository(db);
      final fixturePath = await writeFixtureEpub(tempDir, title: '銀河鉄道の夜');
      final imported = await repo.importEpub(fixturePath);
      await (db.update(db.books)..where((t) => t.id.equals(imported.id))).write(
        const BooksCompanion(readProgress: Value(0.42)),
      );
      await db
          .into(db.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              bookId: imported.id,
              cfi: 'epubcfi(/6/4!/4)',
            ),
          );
      await seedDictionaries(db);
      final dictionaryCount =
          (await db.select(db.dictionaryMetas).get()).length;
      final bookDir = Directory(imported.filePath).parent;
      final booksRoot = bookDir.parent;
      // A loose custom cover in the books root, as the manga cover bug leaves.
      File(
        p.join(booksRoot.path, 'custom_cover_1.png'),
      ).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      // A manga linked from a folder outside Mekuru: only its cache is in
      // books/, the pages are wherever the user keeps them. Plain files stand
      // in for the folder grant through the listing seam; the job still opens
      // them by URI.
      final linkedPagesDir = Directory(p.join(tempDir.path, 'linked'))
        ..createSync();
      final page = tinyPng();
      for (final name in ['001.png', '002.png']) {
        File(p.join(linkedPagesDir.path, name)).writeAsBytesSync(page);
      }
      final linkedDirName = BookRepository.uniqueImportDirName('manga');
      final linkedDir = Directory(p.join(booksRoot.path, linkedDirName))
        ..createSync();
      File(p.join(linkedDir.path, mangaPagesCacheFileName)).writeAsStringSync(
        jsonEncode({
          'title': 'リンク漫画',
          'imageDirPath': '/data/local/tmp/scratch/リンク漫画',
          'safTreeUri': 'content://tree/linked',
          'safImageDirRelativePath': 'Manga/リンク漫画',
          'pages': [],
        }),
      );
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'リンク漫画',
              filePath: linkedDir.path,
              bookType: const Value('manga'),
              coverImagePath: const Value(
                'content://tree/linked/document/001.png',
              ),
            ),
          );
      Future<List<SafTreeFile>> listLinked(String treeUri, String rel) async {
        expect(treeUri, 'content://tree/linked');
        expect(rel, 'Manga/リンク漫画');
        return [
          for (final f in linkedPagesDir.listSync().whereType<File>())
            SafTreeFile(
              name: p.basename(f.path),
              uri: f.uri.toString(),
              size: f.lengthSync(),
              lastModified: f.lastModifiedSync().millisecondsSinceEpoch,
            ),
        ];
      }

      // The downloaded dictionary lives in the documents directory.
      unidicDir.createSync(recursive: true);
      File(p.join(unidicDir.path, '.install_complete')).writeAsStringSync('');
      final dicBytes = Uint8List.fromList(
        List.generate(64 * 1024, (i) => (i * 7) & 0xFF),
      );
      File(p.join(unidicDir.path, 'sys.dic')).writeAsBytesSync(dicBytes);

      final zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
      await realFullBackupService(
        db,
        root,
        documentsRoot: documents,
        listTreeFiles: listLinked,
      ).prepareExport(FullBackupTarget.file(zipPath));
      final exported = await waitForJob(jobIsTerminal, what: 'export');
      expect(exported.lifecycle, FullBackupJobLifecycle.done);
      expect(exported.kind, FullBackupJobKind.export);
      expect(exported.location, zipPath);
      expect(exported.skippedFiles, 0);
      expect(exported.renamed, isTrue);
      expect(File(zipPath).lengthSync(), greaterThan(0));
      expect(File('$zipPath.partial').existsSync(), isFalse);
      // The Kotlin store and the Dart root are the same directory.
      expect(
        File(
          p.join(root.path, StagedFullRestore.jobDirName, 'result.json'),
        ).existsSync(),
        isTrue,
      );
      await fullBackupJobs.consumeResult();

      // ── An independent reader agrees with the writer, byte for byte. ──
      final entries = await readZipWithArchive(zipPath);
      final names = entries.keys.toList();
      expect(names.first, FullBackupManifest.manifestEntry);
      expect(names[1], FullBackupManifest.readmeEntry);
      expect(names[2], FullBackupManifest.settingsEntry);
      expect(names[3], FullBackupManifest.databaseEntry);
      expect(names, contains('Mekuru data/covers/custom_cover_1.png'));
      expect(names.any((n) => n.startsWith('books/')), isFalse);
      final manifest = FullBackupManifest.fromJson(
        jsonDecode(utf8.decode(entries[FullBackupManifest.manifestEntry]!))
            as Map<String, dynamic>,
      );
      expect(manifest.bookCount, 2);
      expect(manifest.dictionaryCount, dictionaryCount);
      expect(manifest.externalMangaCount, 1);
      expect(manifest.folders, {
        'Books/銀河鉄道の夜/': p.basename(bookDir.path),
        'Manga/リンク漫画/': linkedDirName,
      });
      expect(entries['Manga/リンク漫画/pages/001.png'], page);
      expect(entries['Manga/リンク漫画/pages/002.png'], page);
      expect(entries['Mekuru data/unidic-lite/sys.dic'], dicBytes);
      expect(entries['Mekuru data/unidic-lite/.install_complete'], isNotNull);
      final expectedBookFiles = filesUnder(bookDir);
      for (final MapEntry(key: rel, value: bytes)
          in expectedBookFiles.entries) {
        expect(entries['Books/銀河鉄道の夜/$rel'], bytes, reason: rel);
      }
      expect(
        entries.keys.where((n) => n.startsWith('Books/')).length,
        expectedBookFiles.length,
      );
      expect(
        utf8.decode(entries[FullBackupManifest.readmeEntry]!),
        contains('Mekuru full backup'),
      );
      expect(
        BackupSerializer.decode(
          utf8.decode(entries[FullBackupManifest.settingsEntry]!),
        ).settings.app['app.theme_mode'],
        'dark',
      );
      await db.close();

      // ── A new device: nothing in Mekuru, no dictionary, and the folder
      // the manga was linked from does not exist here. ──
      await wipeLiveData();
      linkedPagesDir.deleteSync(recursive: true);
      SharedPreferences.setMockInitialValues({'app.theme_mode': 'light'});
      db = AppDatabase();
      final target = realFullBackupService(db, root, documentsRoot: documents);
      final source = FullBackupSource.file(zipPath);

      final preview = await target.inspect(source);
      expect(preview.manifest.bookCount, 2);
      expect(preview.currentBookCount, 0);

      await target.startRestore(preview);
      final restored = await waitForJob(jobIsTerminal, what: 'restore');
      expect(restored.lifecycle, FullBackupJobLifecycle.done);
      expect(restored.kind, FullBackupJobKind.restore);
      final staging = Directory(
        p.join(root.path, StagedFullRestore.stagingDirName),
      );
      expect(
        File(
          p.join(staging.path, StagedFullRestore.extractedMarkerName),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(staging.path, StagedFullRestore.readyMarkerName),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(staging.path, 'books', p.basename(bookDir.path)),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(staging.path, 'books', 'custom_cover_1.png')).existsSync(),
        isTrue,
      );
      await db.close();

      // ── Next cold start: fix-ups, then the swap. ──
      await applyStagedFullRestoreIfAny();

      db = AppDatabase();
      addTearDown(db.close);
      final books = await db.select(db.books).get();
      expect(books, hasLength(2));
      final novel = books.singleWhere((b) => b.title == '銀河鉄道の夜');
      expect(novel.readProgress, 0.42);
      expect(novel.filePath, startsWith(root.path));
      expect(Directory(novel.filePath).existsSync(), isTrue);
      expect(await db.select(db.bookmarks).get(), hasLength(1));
      // The linked manga is an ordinary one now, reading from pages/.
      final linked = books.singleWhere((b) => b.title == 'リンク漫画');
      final pagesDir = p.join(root.path, 'books', linkedDirName, 'pages');
      expect(linked.coverImagePath, p.join(pagesDir, '001.png'));
      expect(File(linked.coverImagePath!).readAsBytesSync(), page);
      final linkedCache =
          jsonDecode(
                File(
                  p.join(linked.filePath, mangaPagesCacheFileName),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(linkedCache.containsKey('safTreeUri'), isFalse);
      expect(linkedCache.containsKey('safImageDirRelativePath'), isFalse);
      expect(linkedCache['imageDirPath'], pagesDir);
      // The dictionary is back in the documents directory, install marker
      // included, so MeCab picks it up on the next launch.
      expect(await EnhancedFuriganaDictDownloadService.isInstalled(), isTrue);
      expect(
        File(p.join(unidicDir.path, 'sys.dic')).readAsBytesSync(),
        dicBytes,
      );
      expect(
        await db.select(db.dictionaryMetas).get(),
        hasLength(dictionaryCount),
      );
      expect(await db.select(db.dictionaryEntries).get(), isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app.theme_mode'), 'dark');
      expect(prefs.getDouble('reader.font_size'), 22.0);
      expect(
        prefs.getString(StagedFullRestore.resultPrefKey),
        StagedFullRestore.resultOk,
      );
      expect(staging.existsSync(), isFalse);
      expect(
        Directory(
          p.join(root.path, StagedFullRestore.rollbackDirName),
        ).existsSync(),
        isFalse,
      );
      expect(
        (await fullBackupJobs.status()).lifecycle,
        FullBackupJobLifecycle.none,
      );

      // ── The real app boots on the restored database. ──
      await tester.pumpWidget(buildIntegrationTestRealApp(db: db));
      await pumpUntilVisible(
        tester,
        find.byType(NavigationBar),
        timeout: const Duration(seconds: 15),
      );
      await pumpUntilVisible(tester, find.text('銀河鉄道の夜'));
      final l10n = await loadExpectedL10n();
      await pumpUntilVisible(tester, find.text(l10n.backupFullRestoreComplete));
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          StagedFullRestore.resultPrefKey,
        ),
        isFalse,
      );
    },
  );

  testWidgets('a backup from another data root is rewritten onto this device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const foreignRoot = '/data/user/10/moe.matthew.mekuru.other/files';
    final staging = Directory(
      p.join(root.path, StagedFullRestore.stagingDirName),
    )..createSync(recursive: true);

    // What the job leaves behind: rows and caches from the source, in the
    // device layout, plus EXTRACTED and no READY.
    final stagedDb = AppDatabase(
      NativeDatabase(
        File(p.join(staging.path, StagedFullRestore.databaseFileName)),
      ),
    );
    await stagedDb
        .into(stagedDb.books)
        .insert(
          BooksCompanion.insert(
            title: 'Foreign manga',
            filePath: '$foreignRoot/books/manga_77',
            bookType: const Value('manga'),
            coverImagePath: const Value(
              '$foreignRoot/books/manga_77/cover.jpg',
            ),
          ),
        );
    await stagedDb.close();
    final mangaDir = Directory(p.join(staging.path, 'books', 'manga_77'))
      ..createSync(recursive: true);
    File(p.join(mangaDir.path, 'cover.jpg')).writeAsBytesSync([1, 2, 3]);
    Directory(p.join(mangaDir.path, 'pages')).createSync();
    File(p.join(mangaDir.path, 'pages', '001.png')).writeAsBytesSync([4, 5]);
    File(p.join(mangaDir.path, mangaPagesCacheFileName)).writeAsStringSync(
      jsonEncode({
        'title': 'Foreign manga',
        'imageDirPath': '$foreignRoot/books/manga_77/pages',
        'pages': [],
      }),
    );
    File(
      p.join(staging.path, StagedFullRestore.settingsEntryName),
    ).writeAsStringSync(
      BackupSerializer.encode(
        BackupManifest(
          version: BackupManifest.currentVersion,
          createdAt: DateTime.now().toUtc(),
          settings: const BackupSettings(app: {}, reader: {}),
          savedWords: const [],
          books: const [],
        ),
      ),
    );
    File(
      p.join(staging.path, StagedFullRestore.extractedMarkerName),
    ).writeAsStringSync('{"format":1}');

    await applyStagedFullRestoreIfAny();

    final db = AppDatabase();
    addTearDown(db.close);
    final book = (await db.select(db.books).get()).single;
    expect(book.filePath, '${root.path}/books/manga_77');
    expect(book.coverImagePath, '${root.path}/books/manga_77/cover.jpg');
    expect(File(book.coverImagePath!).existsSync(), isTrue);
    final cache =
        jsonDecode(
              File(
                p.join(book.filePath, mangaPagesCacheFileName),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(cache['imageDirPath'], '${root.path}/books/manga_77/pages');
    expect(
      File(p.join(cache['imageDirPath'] as String, '001.png')).existsSync(),
      isTrue,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        StagedFullRestore.resultPrefKey,
      ),
      StagedFullRestore.resultOk,
    );
  });
}
