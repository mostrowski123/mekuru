import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/prepare_staged_restore.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// `prepareStagedRestore` runs in the import step, after extraction and
/// before the READY marker: it validates the staged database and rewrites the
/// absolute paths that the source device baked into rows and manga caches,
/// so that a failure here leaves the live app untouched.
void main() {
  const oldRoot = '/data/user/0/moe.matthew.mekuru.old/files';
  const newRoot = '/data/user/0/moe.matthew.mekuru/files';

  late Directory root;
  late Directory staging;
  late String dbPath;

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  Future<void> seedDatabase({int? userVersion}) async {
    final db = AppDatabase(NativeDatabase(File(dbPath)));
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'EPUB',
            filePath: '$oldRoot/books/book_1/content',
            coverImagePath: const Value('$oldRoot/books/book_1/cover.jpg'),
          ),
        );
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'SAF manga',
            filePath: '$oldRoot/books/manga_2',
            bookType: const Value('manga'),
            coverImagePath: const Value(
              'content://com.android.externalstorage.documents/tree/primary%3AManga/document/cover.jpg',
            ),
          ),
        );
    await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'komga',
            name: 'Home',
            baseUrl: 'https://komga.example',
            enabled: const Value(true),
          ),
        );
    await db.close();
    if (userVersion != null) {
      final raw = sqlite.sqlite3.open(dbPath);
      raw.execute('PRAGMA user_version = $userVersion;');
      raw.close();
    }
  }

  void seedSettings() {
    write(
      p.join(staging.path, StagedFullRestore.settingsEntryName),
      BackupSerializer.encode(
        BackupManifest(
          version: BackupManifest.currentVersion,
          createdAt: DateTime.utc(2026, 9, 7),
          settings: const BackupSettings(app: {}, reader: {}),
          savedWords: const [],
          books: const [],
        ),
      ),
    );
  }

  void seedCaches() {
    write(
      p.join(staging.path, 'books', 'book_1', mangaPagesCacheFileName),
      jsonEncode({
        'title': 'converted',
        'imageDirPath': '$oldRoot/books/book_1/images',
        'pages': [],
      }),
    );
    write(
      p.join(staging.path, 'books', 'manga_2', mangaPagesCacheFileName),
      jsonEncode({
        'title': 'saf',
        'imageDirPath': '/storage/emulated/0/Manga/vol1',
        'safTreeUri': 'content://tree/x',
        'pages': [],
      }),
    );
    write(
      p.join(
        staging.path,
        'books',
        'manga_2',
        BookRepository.originalMokuroOcrBackupFileName,
      ),
      jsonEncode({
        'title': 'saf',
        'imageDirPath': '$oldRoot/books/manga_2/img',
        'pages': [],
      }),
    );
  }

  Future<PreparedStagedRestore> run({String rootPath = newRoot}) =>
      prepareStagedRestore(
        PrepareStagedRestoreArgs(
          stagingPath: staging.path,
          rootPath: rootPath,
          manifestJson: '{"format":1}',
        ),
      );

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  List<Map<String, Object?>> rows(String sql) {
    final raw = sqlite.sqlite3.open(dbPath);
    try {
      return raw.select(sql).map((r) => Map<String, Object?>.from(r)).toList();
    } finally {
      raw.close();
    }
  }

  File readyFile() =>
      File(p.join(staging.path, StagedFullRestore.readyMarkerName));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('prepare_restore_');
    staging = Directory(p.join(root.path, StagedFullRestore.stagingDirName))
      ..createSync();
    dbPath = p.join(staging.path, StagedFullRestore.databaseFileName);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'rewrites book paths from the /books/ anchor onto the new root',
    () async {
      await seedDatabase();
      seedSettings();
      seedCaches();

      final result = await run();

      final books = rows(
        'SELECT title, file_path, cover_image_path FROM books',
      );
      final epub = books.singleWhere((r) => r['title'] == 'EPUB');
      expect(epub['file_path'], '$newRoot/books/book_1/content');
      expect(epub['cover_image_path'], '$newRoot/books/book_1/cover.jpg');
      final manga = books.singleWhere((r) => r['title'] == 'SAF manga');
      expect(manga['file_path'], '$newRoot/books/manga_2');
      expect(manga['cover_image_path'], startsWith('content://'));
      expect(result.rewrittenBooks, 2);
    },
  );

  test(
    'rewrites imageDirPath in both manga cache files, not SAF dirs',
    () async {
      await seedDatabase();
      seedSettings();
      seedCaches();

      await run();

      expect(
        readJson(
          p.join(staging.path, 'books', 'book_1', mangaPagesCacheFileName),
        )['imageDirPath'],
        '$newRoot/books/book_1/images',
      );
      final saf = readJson(
        p.join(staging.path, 'books', 'manga_2', mangaPagesCacheFileName),
      );
      expect(saf['imageDirPath'], '/storage/emulated/0/Manga/vol1');
      expect(saf['safTreeUri'], 'content://tree/x');
      expect(
        readJson(
          p.join(
            staging.path,
            'books',
            'manga_2',
            BookRepository.originalMokuroOcrBackupFileName,
          ),
        )['imageDirPath'],
        '$newRoot/books/manga_2/img',
      );
    },
  );

  test('adopts the pages of a linked manga the archive carries', () async {
    await seedDatabase();
    seedSettings();
    seedCaches();
    for (final name in ['002.jpg', '001.png', 'notes.txt']) {
      write(p.join(staging.path, 'books', 'manga_2', 'pages', name), name);
    }

    final result = await run();
    // A second boot (crash after READY was lost) must land in the same place.
    await run();

    const pagesDir = '$newRoot/books/manga_2/pages';
    final cache = readJson(
      p.join(staging.path, 'books', 'manga_2', mangaPagesCacheFileName),
    );
    expect(cache['imageDirPath'], pagesDir);
    expect(cache.containsKey('safTreeUri'), isFalse);
    expect(cache.containsKey('safImageDirRelativePath'), isFalse);
    // The original-OCR copy was already local in this fixture: re-anchored.
    expect(
      readJson(
        p.join(
          staging.path,
          'books',
          'manga_2',
          BookRepository.originalMokuroOcrBackupFileName,
        ),
      )['imageDirPath'],
      '$newRoot/books/manga_2/img',
    );
    final manga = rows(
      "SELECT cover_image_path FROM books WHERE title = 'SAF manga'",
    ).single;
    expect(manga['cover_image_path'], '$pagesDir/001.png');
    expect(result.rewrittenCaches, 3);
  });

  test('is idempotent and tolerates a trailing slash on the root', () async {
    await seedDatabase();
    seedSettings();
    seedCaches();

    await run(rootPath: '$newRoot/');
    await run(rootPath: newRoot);

    final epub = rows("SELECT file_path FROM books WHERE title = 'EPUB'");
    expect(epub.single['file_path'], '$newRoot/books/book_1/content');
    expect(
      readJson(
        p.join(staging.path, 'books', 'book_1', mangaPagesCacheFileName),
      )['imageDirPath'],
      '$newRoot/books/book_1/images',
    );
  });

  test('disables server connections and returns their ids', () async {
    await seedDatabase();
    seedSettings();

    final result = await run();

    final connections = rows('SELECT id, enabled FROM server_connections');
    expect(connections.single['enabled'], 0);
    expect(result.serverConnectionIds, [connections.single['id']]);
  });

  test('creates an empty books dir when the archive had no books', () async {
    await seedDatabase();
    seedSettings();

    await run();

    expect(Directory(p.join(staging.path, 'books')).existsSync(), isTrue);
    expect(readyFile().existsSync(), isTrue);
  });

  test('writes READY last with the manifest as its content', () async {
    await seedDatabase();
    seedSettings();

    await run();

    expect(readyFile().readAsStringSync(), '{"format":1}');
  });

  test('rejects a database schema newer than this build', () async {
    await seedDatabase(userVersion: AppDatabase.latestSchemaVersion + 1);
    seedSettings();

    await expectLater(run(), throwsA(isA<FullBackupFormatException>()));
    expect(readyFile().existsSync(), isFalse);
  });

  test('rejects a corrupt database', () async {
    write(dbPath, 'this is not a sqlite file at all, not even close');
    seedSettings();

    await expectLater(run(), throwsA(isA<FullBackupFormatException>()));
    expect(readyFile().existsSync(), isFalse);
  });

  test('rejects staging without settings.mekuru', () async {
    await seedDatabase();

    await expectLater(run(), throwsA(isA<FullBackupFormatException>()));
    expect(readyFile().existsSync(), isFalse);
  });

  test('rejects staging without a database', () async {
    seedSettings();

    await expectLater(run(), throwsA(isA<FullBackupFormatException>()));
    expect(readyFile().existsSync(), isFalse);
  });

  // The staging dir has the live layout (database + books/ side by side), so
  // it stands in for an app-support root whose container path just changed.
  group('reanchorLibraryIfMoved', () {
    test(
      'moves rows and caches onto the root the library now lives under',
      () async {
        await seedDatabase();
        seedCaches();
        final liveRoot = staging.path;

        expect(await reanchorLibraryIfMoved('$liveRoot/'), isTrue);

        final books = rows(
          'SELECT title, file_path, cover_image_path FROM books',
        );
        final epub = books.singleWhere((r) => r['title'] == 'EPUB');
        expect(epub['file_path'], '$liveRoot/books/book_1/content');
        expect(epub['cover_image_path'], '$liveRoot/books/book_1/cover.jpg');
        final manga = books.singleWhere((r) => r['title'] == 'SAF manga');
        expect(manga['file_path'], '$liveRoot/books/manga_2');
        expect(manga['cover_image_path'], startsWith('content://'));
        expect(
          readJson(
            p.join(liveRoot, 'books', 'book_1', mangaPagesCacheFileName),
          )['imageDirPath'],
          '$liveRoot/books/book_1/images',
        );
      },
    );

    test('is a no-op once the library is on the current root', () async {
      await seedDatabase();
      seedCaches();
      await reanchorLibraryIfMoved(staging.path);
      final cache = File(
        p.join(staging.path, 'books', 'book_1', mangaPagesCacheFileName),
      );
      final before = cache.lastModifiedSync();

      expect(await reanchorLibraryIfMoved(staging.path), isFalse);
      expect(cache.lastModifiedSync(), before);
    });

    test('redoes the caches when a pass died before the database', () async {
      await seedDatabase();
      seedCaches();
      // Rows still on the old root are the "moved" signal, whatever state
      // the caches were left in.
      await reanchorLibraryIfMoved(staging.path);
      final raw = sqlite.sqlite3.open(dbPath);
      raw.execute(
        "UPDATE books SET file_path = '$oldRoot/books/book_1/content' "
        "WHERE title = 'EPUB'",
      );
      raw.close();

      expect(await reanchorLibraryIfMoved(staging.path), isTrue);
      expect(
        rows(
          "SELECT file_path FROM books WHERE title = 'EPUB'",
        ).single['file_path'],
        '${staging.path}/books/book_1/content',
      );
    });

    test('does nothing, and creates nothing, on a fresh install', () async {
      expect(await reanchorLibraryIfMoved(staging.path), isFalse);
      expect(File(dbPath).existsSync(), isFalse);
    });
  });
}
