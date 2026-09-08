import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../shared/test_database.dart';
import 'fake_full_backup_job_api.dart';

/// `FullBackupService` prepares everything the native job needs (snapshot,
/// sidecars, plan) and commits it; the job service is faked, the database,
/// the snapshot and the plan are real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const safChannel = MethodChannel('mekuru/android_saf');

  late Directory root;
  late AppDatabase db;
  late FakeFullBackupJobApi jobs;
  late FullBackupService service;
  var freeBytes = 1 << 40;

  Directory booksDir() =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));
  Directory staging() =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));
  Directory jobDir() =>
      Directory(p.join(root.path, StagedFullRestore.jobDirName));

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String manifestJson({
    int schemaVersion = AppDatabase.latestSchemaVersion,
    int booksBytes = 4000,
  }) => jsonEncode(
    FullBackupManifest(
      format: FullBackupManifest.currentFormat,
      appVersion: '1.37.0',
      schemaVersion: schemaVersion,
      createdAt: DateTime.utc(2026, 9, 1),
      appSupportPath: '/data/user/0/old/files',
      bookCount: 7,
      dictionaryCount: 3,
      externalMangaCount: 1,
      dbBytes: 1000,
      booksBytes: booksBytes,
      folders: const {'Books/走れメロス/': 'book_1_aaaaaaaa'},
    ).toJson(),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('full_backup_root_');
    booksDir().createSync();
    SharedPreferences.setMockInitialValues({'app.theme_mode': 'dark'});
    freeBytes = 1 << 40;
    jobs = FakeFullBackupJobApi();

    db = createTestDatabase();
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '走れメロス',
            filePath: '${root.path}/books/book_1_aaaaaaaa/content',
          ),
        );
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'External manga',
            filePath: '${root.path}/books/manga_2_bbbbbbbb',
            bookType: const Value('manga'),
            coverImagePath: const Value('content://tree/cover.jpg'),
          ),
        );
    write(p.join(booksDir().path, 'book_1_aaaaaaaa', 'メロス.epub'), 'EPUB');
    write(
      p.join(booksDir().path, 'book_1_aaaaaaaa', 'content', 'a.xhtml'),
      'A',
    );
    write(
      p.join(booksDir().path, 'manga_2_bbbbbbbb', 'pages_cache.json'),
      '{}',
    );
    write(p.join(booksDir().path, 'custom_cover_1.jpg'), 'JPG');
    final dictionaries = DictionaryRepository(db);
    await dictionaries.insertDictionary('JMdict');
    final hiddenId = await dictionaries.insertDictionary('Bundled frequency');
    await (db.update(db.dictionaryMetas)..where((t) => t.id.equals(hiddenId)))
        .write(const DictionaryMetasCompanion(isHidden: Value(true)));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safChannel, (call) async {
          if (call.method == 'getFreeBytes') return freeBytes;
          throw PlatformException(code: 'unmocked', message: call.method);
        });

    service = FullBackupService(
      db: db,
      backupService: BackupService(db, BookMatchService()),
      root: root,
      appVersion: '1.38.0',
      jobs: jobs,
      clock: () => DateTime(2026, 9, 8, 10, 30, 15),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safChannel, null);
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('prepareExport', () {
    test('writes the snapshot, sidecars and plan, then commits', () async {
      write(p.join(root.path, StagedFullRestore.databaseFileName), 'x' * 1234);
      final target = p.join(root.path, 'out', 'mekuru-full-backup.zip');

      await service.prepareExport(FullBackupTarget.file(target));

      final planLines =
          File(p.join(jobDir().path, FullBackupService.planFileName))
              .readAsLinesSync()
              .map((l) => jsonDecode(l) as Map<String, dynamic>)
              .toList();
      expect(planLines.map((l) => l['n']).take(4), [
        FullBackupManifest.manifestEntry,
        FullBackupManifest.readmeEntry,
        FullBackupManifest.settingsEntry,
        FullBackupManifest.databaseEntry,
      ]);
      expect(planLines.take(4).every((l) => l['l'] == 6), isTrue);
      expect(planLines.skip(4).map((l) => l['n']), [
        'Mekuru data/covers/custom_cover_1.jpg',
        'Books/走れメロス/content/a.xhtml',
        'Books/走れメロス/メロス.epub',
        'Manga/External manga/pages_cache.json',
      ]);
      expect(planLines.skip(4).every((l) => l['l'] == 0), isTrue);
      for (final line in planLines) {
        expect(File(line['p'] as String).lengthSync(), line['s']);
      }

      final manifest = FullBackupManifest.fromJson(
        jsonDecode(
              File(p.join(jobDir().path, 'manifest.json')).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(manifest.appVersion, '1.38.0');
      expect(manifest.schemaVersion, AppDatabase.latestSchemaVersion);
      expect(manifest.appSupportPath, root.path);
      expect(manifest.bookCount, 2);
      expect(manifest.dictionaryCount, 1);
      expect(manifest.externalMangaCount, 1);
      expect(manifest.folders, {
        'Books/走れメロス/': 'book_1_aaaaaaaa',
        'Manga/External manga/': 'manga_2_bbbbbbbb',
      });
      final snapshot = File(
        p.join(jobDir().path, AppDatabase.databaseFileName),
      );
      expect(manifest.dbBytes, snapshot.lengthSync());
      expect(manifest.booksBytes, 3 + 1 + 4 + 2);
      final raw = sqlite.sqlite3.open(snapshot.path);
      expect(
        raw.select('SELECT count(*) AS c FROM dictionary_metas').first['c'],
        2,
      );
      raw.close();
      expect(
        File(p.join(jobDir().path, 'README.txt')).readAsStringSync(),
        contains('Mekuru full backup'),
      );
      expect(
        BackupSerializer.decode(
          File(p.join(jobDir().path, 'settings.mekuru')).readAsStringSync(),
        ).settings.app['app.theme_mode'],
        'dark',
      );

      final spec = jobs.committed.single;
      expect(spec['kind'], 'export');
      expect(spec['targetPath'], target);
      expect(spec['displayName'], 'mekuru-full-backup.zip');
      expect(spec.containsKey('treeUri'), isFalse);
      expect(
        spec['totalBytes'],
        planLines.fold<int>(0, (sum, l) => sum + (l['s'] as int)),
      );
    });

    test('names a folder export by timestamp', () async {
      await service.prepareExport(
        const FullBackupTarget.tree('content://tree/backups'),
      );
      final spec = jobs.committed.single;
      expect(spec['treeUri'], 'content://tree/backups');
      expect(spec['displayName'], 'mekuru-full-backup-20260908-103015.zip');
      expect(spec.containsKey('targetPath'), isFalse);
    });

    test('is refused while a book import is in flight', () async {
      BookRepository.inFlightImportDirNames.add('book_test_inflight');
      addTearDown(
        () =>
            BookRepository.inFlightImportDirNames.remove('book_test_inflight'),
      );
      await expectLater(
        service.prepareExport(
          FullBackupTarget.file(p.join(root.path, 'o.zip')),
        ),
        throwsA(isA<FullBackupBusyException>()),
      );
      expect(jobs.committed, isEmpty);
    });

    test('is refused while another job exists', () async {
      jobs.current = const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.paused,
      );
      await expectLater(
        service.prepareExport(
          FullBackupTarget.file(p.join(root.path, 'o.zip')),
        ),
        throwsA(isA<FullBackupBusyException>()),
      );
      expect(jobDir().existsSync(), isFalse);
    });

    test('reports the space it needs before writing anything', () async {
      write(p.join(root.path, StagedFullRestore.databaseFileName), 'x' * 1000);
      freeBytes = 100;
      await expectLater(
        service.prepareExport(
          FullBackupTarget.file(p.join(root.path, 'o.zip')),
        ),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            greaterThan(0),
          ),
        ),
      );
      expect(jobs.committed, isEmpty);
      expect(
        jobDir().existsSync()
            ? jobDir().listSync()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('a service that turned busy keeps the other job untouched', () async {
      // The other job committed between our status check and our commit.
      final theirs = write(p.join(jobDir().path, 'job.json'), '{"kind":"x"}');
      jobs.commitError = const FullBackupJobBusyException();
      await expectLater(
        service.prepareExport(
          FullBackupTarget.file(p.join(root.path, 'o.zip')),
        ),
        throwsA(isA<FullBackupBusyException>()),
      );
      expect(theirs.existsSync(), isTrue);
    });

    test('a failed preparation removes only its own files', () async {
      final foreign = write(p.join(jobDir().path, 'result.json'), '{}');
      write(p.join(root.path, StagedFullRestore.databaseFileName), 'x' * 1000);
      freeBytes = 100;
      await expectLater(
        service.prepareExport(
          FullBackupTarget.file(p.join(root.path, 'o.zip')),
        ),
        throwsA(isA<InsufficientSpaceException>()),
      );
      expect(foreign.existsSync(), isTrue);
      expect(
        File(p.join(jobDir().path, AppDatabase.databaseFileName)).existsSync(),
        isFalse,
      );
    });
  });

  group('inspect', () {
    late FullBackupSource source;

    setUp(() {
      source = FullBackupSource.file(
        write(p.join(root.path, 'picked.zip'), 'PK...').path,
      );
      jobs.inspection = ZipInspection(
        isZip: true,
        text: manifestJson(),
        complete: true,
      );
    });

    test(
      'returns the manifest with what Mekuru holds on this device',
      () async {
        final preview = await service.inspect(source);
        expect(preview.manifest.bookCount, 7);
        expect(preview.manifest.folders, {'Books/走れメロス/': 'book_1_aaaaaaaa'});
        expect(preview.source, source);
        expect(preview.sizeBytes, 5);
        expect(preview.currentBookCount, 2);
        expect(preview.currentDictionaryCount, 1);
      },
    );

    test('rejects an archive from a newer app', () async {
      jobs.inspection = ZipInspection(
        isZip: true,
        text: manifestJson(schemaVersion: AppDatabase.latestSchemaVersion + 1),
      );
      await expectLater(
        service.inspect(source),
        throwsA(isA<FullBackupTooNewException>()),
      );
    });

    test('names the other kind when a .mekuru file is picked', () async {
      jobs.inspection = const ZipInspection(isZip: false);
      await expectLater(
        service.inspect(source),
        throwsA(
          isA<WrongBackupKindException>().having(
            (e) => e.found,
            'found',
            BackupKind.readingData,
          ),
        ),
      );
    });

    test('rejects a zip that is not a Mekuru full backup', () async {
      jobs.inspection = const ZipInspection(isZip: true, text: null);
      await expectLater(
        service.inspect(source),
        throwsA(isA<FullBackupFormatException>()),
      );
    });

    test('rejects a zip without an end record as incomplete', () async {
      jobs.inspection = ZipInspection(
        isZip: true,
        text: manifestJson(),
        complete: false,
      );
      await expectLater(
        service.inspect(source),
        throwsA(isA<FullBackupIncompleteException>()),
      );
    });

    test('an unknown end record (unseekable source) is accepted', () async {
      jobs.inspection = ZipInspection(isZip: true, text: manifestJson());
      expect((await service.inspect(source)).manifest.bookCount, 7);
    });

    test('reports missing space from the manifest sizes', () async {
      freeBytes = 10;
      await expectLater(
        service.inspect(source),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            greaterThanOrEqualTo(5000 - 10),
          ),
        ),
      );
    });

    test('refuses while a previous restore is waiting to be applied', () async {
      for (final marker in [
        StagedFullRestore.readyMarkerName,
        StagedFullRestore.extractedMarkerName,
      ]) {
        final file = write(p.join(staging().path, marker), '{}');
        await expectLater(
          service.inspect(source),
          throwsA(isA<FullBackupPendingRestoreException>()),
        );
        file.deleteSync();
      }
    });

    test('refuses while a job is running', () async {
      jobs.current = const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
      );
      await expectLater(
        service.inspect(source),
        throwsA(isA<FullBackupBusyException>()),
      );
      expect(jobs.calls, isNot(contains('inspectZip')));
    });
  });

  group('startRestore', () {
    test('commits a restore job with the archive map and manifest', () async {
      final source = FullBackupFileSource(
        write(p.join(root.path, 'picked.zip'), 'PK...').path,
      );
      jobs.inspection = ZipInspection(isZip: true, text: manifestJson());
      final preview = await service.inspect(source);

      await service.startRestore(preview);

      final spec = jobs.committed.single;
      expect(spec['kind'], 'restore');
      expect(spec['sourceUri'], Uri.file(source.path).toString());
      expect(spec['stagingPath'], staging().path);
      expect(spec['totalBytes'], 5000);
      expect(spec['folders'], {'Books/走れメロス/': 'book_1_aaaaaaaa'});
      final manifest = FullBackupManifest.fromJson(
        jsonDecode(spec['manifestJson'] as String) as Map<String, dynamic>,
      );
      expect(manifest.bookCount, 7);
    });

    test('passes a document URI through unchanged', () async {
      jobs.inspection = ZipInspection(isZip: true, text: manifestJson());
      final preview = await service.inspect(
        const FullBackupSource.uri('content://doc/a.zip', sizeBytes: 9),
      );
      await service.startRestore(preview);
      expect(jobs.committed.single['sourceUri'], 'content://doc/a.zip');
    });
  });
}
