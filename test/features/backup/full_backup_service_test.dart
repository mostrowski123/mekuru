import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
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

/// `FullBackupService` orchestrates the archive: it snapshots the database,
/// writes the sidecar files and drives the native zip through the SAF
/// channel. The channel is mocked here; the database, the snapshot and the
/// staging fix-ups are real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mekuru/android_saf');

  late Directory root;
  late Directory cache;
  late AppDatabase db;
  late FullBackupService service;
  late List<MethodCall> calls;
  late Map<String, Future<Object?> Function(MethodCall call)> handlers;
  late List<int> clearedSecrets;
  var freeBytes = 1 << 40;

  Directory booksDir() =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));
  Directory staging() =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));
  Directory exportDir() =>
      Directory(p.join(cache.path, FullBackupService.exportDirName));

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String manifestJson({int schemaVersion = AppDatabase.latestSchemaVersion}) =>
      jsonEncode(
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
          booksBytes: 4000,
          entryCount: 20,
        ).toJson(),
      );

  String encodedSettings() => BackupSerializer.encode(
    BackupManifest(
      version: BackupManifest.currentVersion,
      createdAt: DateTime.utc(2026, 9, 1),
      settings: const BackupSettings(
        app: {'app.theme_mode': 'dark'},
        reader: {},
      ),
      savedWords: const [],
      books: const [],
    ),
  );

  /// Builds a real, closed sqlite file the mocked extractor can "extract".
  Future<File> buildRestorableDatabase(Directory dir) async {
    final file = File(p.join(dir.path, StagedFullRestore.databaseFileName));
    final source = AppDatabase(NativeDatabase(file));
    await source
        .into(source.books)
        .insert(
          BooksCompanion.insert(
            title: 'Restored',
            filePath: '/data/user/0/old/files/books/book_1/content',
          ),
        );
    await source
        .into(source.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'komga',
            name: 'Home',
            baseUrl: 'https://komga.example',
            enabled: const Value(true),
          ),
        );
    await source.close();
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('full_backup_root_');
    cache = await Directory.systemTemp.createTemp('full_backup_cache_');
    booksDir().createSync();
    SharedPreferences.setMockInitialValues({'app.theme_mode': 'dark'});
    freeBytes = 1 << 40;
    calls = [];
    clearedSecrets = [];

    db = createTestDatabase();
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: 'EPUB', filePath: '/a/books/b'));
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'External manga',
            filePath: '/a/books/m',
            bookType: const Value('manga'),
            coverImagePath: const Value('content://tree/cover.jpg'),
          ),
        );
    final dictionaries = DictionaryRepository(db);
    await dictionaries.insertDictionary('JMdict');
    final hiddenId = await dictionaries.insertDictionary('Bundled frequency');
    await (db.update(db.dictionaryMetas)..where((t) => t.id.equals(hiddenId)))
        .write(const DictionaryMetasCompanion(isHidden: Value(true)));

    handlers = {
      'getFreeBytes': (_) async => freeBytes,
      'measureTree': (_) async => {'bytes': 5000, 'files': 12},
      'zipProgress': (_) async => {'done': 0, 'total': 0},
      'cancelZip': (_) async => null,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final handler = handlers[call.method];
          if (handler == null) {
            throw PlatformException(code: 'unmocked', message: call.method);
          }
          return handler(call);
        });

    service = FullBackupService(
      db: db,
      backupService: BackupService(db, BookMatchService()),
      root: root,
      cacheDir: cache,
      appVersion: '1.38.0',
      clearServerSecret: (id) async => clearedSecrets.add(id),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
    for (final dir in [root, cache]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  Map<Object?, Object?> args(MethodCall call) =>
      Map<Object?, Object?>.from(call.arguments as Map);

  group('export', () {
    test(
      'snapshots the database and hands the native zip a complete plan',
      () async {
        write(
          p.join(root.path, StagedFullRestore.databaseFileName),
          'x' * 1234,
        );
        Map<Object?, Object?>? zipArgs;
        String? manifestText;
        String? settingsText;
        var snapshotDictionaries = -1;
        var snapshotBytes = -1;
        handlers['writeZipToFile'] = (call) async {
          zipArgs = args(call);
          final files = (zipArgs!['files'] as List)
              .map((e) => Map<Object?, Object?>.from(e as Map))
              .toList();
          manifestText = File(files[0]['path'] as String).readAsStringSync();
          settingsText = File(files[1]['path'] as String).readAsStringSync();
          snapshotBytes = File(files[2]['path'] as String).lengthSync();
          final snapshot = sqlite.sqlite3.open(files[2]['path'] as String);
          snapshotDictionaries =
              snapshot
                      .select('SELECT count(*) AS c FROM dictionary_metas')
                      .first['c']
                  as int;
          snapshot.close();
          return {'bytes': 777, 'entries': 15, 'skippedFiles': 0};
        };
        final target = p.join(cache.path, 'out.zip');

        final result = await service.export(FullBackupTarget.file(target));

        expect(zipArgs!['path'], target);
        expect(zipArgs!['excludeDirNames'], ['.trash']);
        expect(zipArgs!['roots'], [
          {'path': booksDir().path, 'prefix': FullBackupManifest.booksPrefix},
        ]);
        final files = (zipArgs!['files'] as List)
            .map((e) => Map<Object?, Object?>.from(e as Map))
            .toList();
        expect(files.map((f) => f['name']), [
          FullBackupManifest.manifestEntry,
          FullBackupManifest.settingsEntry,
          FullBackupManifest.databaseEntry,
        ]);
        expect(files.every((f) => f['level'] == 6), isTrue);

        final manifest = FullBackupManifest.fromJson(
          jsonDecode(manifestText!) as Map<String, dynamic>,
        );
        expect(manifest.appVersion, '1.38.0');
        expect(manifest.schemaVersion, AppDatabase.latestSchemaVersion);
        expect(manifest.appSupportPath, root.path);
        expect(manifest.bookCount, 2);
        expect(manifest.dictionaryCount, 1);
        expect(manifest.externalMangaCount, 1);
        // The restore needs room for the snapshot, not the live file.
        expect(snapshotBytes, greaterThan(0));
        expect(manifest.dbBytes, snapshotBytes);
        expect(manifest.booksBytes, 5000);
        expect(manifest.entryCount, 15);
        expect(
          BackupSerializer.decode(settingsText!).settings.app['app.theme_mode'],
          'dark',
        );
        expect(snapshotDictionaries, 2);

        expect(result.location, target);
        expect(result.bytes, 777);
        expect(result.entries, 15);
        expect(result.skippedFiles, 0);
        expect(result.manifest.bookCount, 2);
        expect(exportDir().existsSync(), isFalse);
      },
    );

    test('is refused while a book import is in flight', () async {
      BookRepository.inFlightImportDirNames.add('book_test_inflight');
      addTearDown(
        () =>
            BookRepository.inFlightImportDirNames.remove('book_test_inflight'),
      );

      await expectLater(
        service.export(FullBackupTarget.file(p.join(cache.path, 'o.zip'))),
        throwsA(isA<FullBackupBusyException>()),
      );
      expect(calls.where((c) => c.method == 'writeZipToFile'), isEmpty);
    });

    test('reports the space it needs before writing anything', () async {
      write(p.join(root.path, StagedFullRestore.databaseFileName), 'x' * 1000);
      freeBytes = 100;

      await expectLater(
        service.export(FullBackupTarget.file(p.join(cache.path, 'o.zip'))),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            greaterThan(0),
          ),
        ),
      );
      expect(calls.where((c) => c.method == 'writeZipToFile'), isEmpty);
      expect(exportDir().existsSync(), isFalse);
    });

    test(
      'uses the tree writer and a timestamped name for a folder target',
      () async {
        Map<Object?, Object?>? zipArgs;
        handlers['writeZipToTree'] = (call) async {
          zipArgs = args(call);
          return {
            'documentUri': 'content://tree/doc.zip',
            'bytes': 1,
            'entries': 3,
            'skippedFiles': 0,
          };
        };

        final result = await service.export(
          const FullBackupTarget.tree('content://tree/backups'),
        );

        expect(zipArgs!['treeUri'], 'content://tree/backups');
        expect(
          zipArgs!['displayName'],
          matches(RegExp(r'^mekuru-full-backup-\d{8}-\d{6}\.zip$')),
        );
        expect(result.location, 'content://tree/doc.zip');
      },
    );
  });

  group('inspect', () {
    late String zipPath;

    setUp(() {
      zipPath = write(p.join(cache.path, 'picked.zip'), 'PK...').path;
    });

    test(
      'returns the manifest with what Mekuru holds on this device',
      () async {
        handlers['peekZipEntryText'] = (call) async {
          expect(args(call)['name'], FullBackupManifest.manifestEntry);
          return {'isZip': true, 'text': manifestJson()};
        };

        final preview = await service.inspect(FullBackupSource.file(zipPath));

        expect(preview.manifest.bookCount, 7);
        expect(preview.manifest.appVersion, '1.37.0');
        expect(preview.sizeBytes, 5);
        expect(preview.currentBookCount, 2);
        expect(preview.currentDictionaryCount, 1);
      },
    );

    test('rejects an archive from a newer app', () async {
      handlers['peekZipEntryText'] = (_) async => {
        'isZip': true,
        'text': manifestJson(schemaVersion: 99),
      };

      await expectLater(
        service.inspect(FullBackupSource.file(zipPath)),
        throwsA(isA<FullBackupTooNewException>()),
      );
    });

    test('names the other kind when a .mekuru file is picked', () async {
      handlers['peekZipEntryText'] = (_) async => {'isZip': false};

      await expectLater(
        service.inspect(FullBackupSource.file(zipPath)),
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
      handlers['peekZipEntryText'] = (_) async => {'isZip': true, 'text': null};

      await expectLater(
        service.inspect(FullBackupSource.file(zipPath)),
        throwsA(isA<FullBackupFormatException>()),
      );
    });

    test('reports missing space from the manifest sizes', () async {
      handlers['peekZipEntryText'] = (_) async => {
        'isZip': true,
        'text': manifestJson(),
      };
      freeBytes = 10;

      await expectLater(
        service.inspect(FullBackupSource.file(zipPath)),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            greaterThanOrEqualTo(5000 - 10),
          ),
        ),
      );
    });

    test(
      'refuses while a previous restore is still waiting to be applied',
      () async {
        handlers['peekZipEntryText'] = (_) async => {
          'isZip': true,
          'text': manifestJson(),
        };
        write(p.join(staging().path, StagedFullRestore.readyMarkerName), '{}');

        await expectLater(
          service.inspect(FullBackupSource.file(zipPath)),
          throwsA(isA<FullBackupPendingRestoreException>()),
        );
      },
    );
  });

  group('stage', () {
    late String zipPath;
    late Directory source;

    setUp(() async {
      zipPath = write(p.join(cache.path, 'picked.zip'), 'PK...').path;
      source = Directory(p.join(cache.path, 'source'))..createSync();
      await buildRestorableDatabase(source);
      write(
        p.join(source.path, FullBackupManifest.settingsEntry),
        encodedSettings(),
      );
      write(p.join(source.path, 'books', 'book_1', 'content', 'x.txt'), 'x');
    });

    /// Mock extractor: copies [source] into the requested destination.
    Future<Object?> extractFrom(Directory from, MethodCall call) async {
      final dest = Directory(args(call)['destPath'] as String);
      var entries = 0;
      await for (final entity in from.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: from.path);
        final target = File(p.join(dest.path, rel));
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
        entries++;
      }
      return {'entries': entries};
    }

    test(
      'extracts, fixes up the database, clears secrets and writes READY',
      () async {
        handlers['extractZipFromFile'] = (call) => extractFrom(source, call);
        write(
          p.join(root.path, StagedFullRestore.rollbackDirName, 'stale.txt'),
          'stale',
        );

        final prepared = await service.stage(FullBackupSource.file(zipPath));

        expect(prepared.serverConnectionIds, hasLength(1));
        expect(clearedSecrets, prepared.serverConnectionIds);
        expect(
          File(
            p.join(staging().path, StagedFullRestore.readyMarkerName),
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory(
            p.join(staging().path, StagedFullRestore.booksDirName),
          ).existsSync(),
          isTrue,
        );
        final restoredDb = sqlite.sqlite3.open(
          p.join(staging().path, StagedFullRestore.databaseFileName),
        );
        final row = restoredDb.select('SELECT file_path FROM books').first;
        restoredDb.close();
        expect(row['file_path'], '${root.path}/books/book_1/content');
        expect(
          Directory(
            p.join(root.path, StagedFullRestore.rollbackDirName),
          ).existsSync(),
          isFalse,
        );
        expect(
          calls.map((c) => c.method),
          containsAllInOrder(['extractZipFromFile']),
        );
      },
    );

    test('a failed extraction leaves no staging directory', () async {
      handlers['extractZipFromFile'] = (_) async =>
          throw PlatformException(code: 'saf_read_failed', message: 'boom');

      await expectLater(
        service.stage(FullBackupSource.file(zipPath)),
        throwsA(isA<PlatformException>()),
      );
      expect(staging().existsSync(), isFalse);
    });

    test(
      'an archive that fails validation leaves no staging directory',
      () async {
        File(
          p.join(source.path, FullBackupManifest.settingsEntry),
        ).deleteSync();
        handlers['extractZipFromFile'] = (call) => extractFrom(source, call);

        await expectLater(
          service.stage(FullBackupSource.file(zipPath)),
          throwsA(isA<FullBackupFormatException>()),
        );
        expect(staging().existsSync(), isFalse);
        expect(clearedSecrets, isEmpty);
      },
    );
  });

  test('cancel forwards to the native archiver', () async {
    await service.cancel();
    expect(calls.map((c) => c.method), contains('cancelZip'));
  });
}
