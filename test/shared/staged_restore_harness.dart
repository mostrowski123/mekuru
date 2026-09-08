import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Lays out a fake app-support root for [StagedFullRestore] tests: an "old"
/// device (database + hot journal + one book) and a staged "new" one.
///
/// Shared by the host unit suite (state machine) and the emulator suite
/// (real filesystem semantics) so both run the identical scenarios.
class StagedRestoreHarness {
  StagedRestoreHarness({required this.root, required this.prefs});

  final Directory root;
  final SharedPreferences prefs;

  /// Server connection ids whose secrets the boot fix-ups cleared.
  final clearedSecrets = <int>[];

  /// Every error a [run] reported, for failure messages.
  final errors = <Object>[];

  static const db = StagedFullRestore.databaseFileName;
  static const journal = '$db-journal';

  /// Preferences the wipe must drop, keep, or replace.
  static const initialPrefs = <String, Object>{
    'app.theme_mode': 'light',
    'ocr.progress.5': 12,
    'ocr.pending_finalizations': '["job-1"]',
    'review_prompt.request_count': 2,
    'backup.last_auto_at': '2026-09-01T00:00:00Z',
  };

  Directory get staging =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));
  Directory get rollback =>
      Directory(p.join(root.path, StagedFullRestore.rollbackDirName));
  File get ready =>
      File(p.join(staging.path, StagedFullRestore.readyMarkerName));
  File get extracted =>
      File(p.join(staging.path, StagedFullRestore.extractedMarkerName));
  File get jobCancelled => File(
    p.join(
      root.path,
      StagedFullRestore.jobDirName,
      StagedFullRestore.cancelledMarkerName,
    ),
  );
  Directory get liveBooks =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));
  File get liveDb => File(p.join(root.path, db));
  File get liveJournal => File(p.join(root.path, journal));

  /// Stands in for the app-documents directory, a sibling of app support.
  Directory get documentsRoot => Directory(p.join(root.path, 'app_flutter'));
  File get liveDictionary => File(
    p.join(documentsRoot.path, StagedFullRestore.unidicDirName, 'sys.dic'),
  );

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String read(String path) => File(path).readAsStringSync();

  static String encodedSettings() => BackupSerializer.encode(
    BackupManifest(
      version: BackupManifest.currentVersion,
      createdAt: DateTime.utc(2026, 9, 7),
      settings: const BackupSettings(
        app: {'app.theme_mode': 'dark', 'app.color_theme': 'mekuruRed'},
        reader: {'reader.font_size': 20.0},
      ),
      savedWords: const [],
      books: const [],
    ),
  );

  /// The device before the restore: old DB with a hot journal, one old book,
  /// optionally a downloaded dictionary.
  void seedLive({bool withDictionary = false}) {
    write(liveDb.path, 'OLD-DB');
    write(liveJournal.path, 'OLD-JOURNAL');
    write(p.join(liveBooks.path, 'book_1', 'a.txt'), 'old book');
    if (withDictionary) write(liveDictionary.path, 'OLD-DIC');
  }

  /// What the import step leaves behind, READY written last.
  void seedStaging({
    bool withDb = true,
    bool withBooks = true,
    bool withDictionary = false,
  }) {
    if (withDb) write(p.join(staging.path, db), 'NEW-DB');
    if (withBooks) {
      write(p.join(staging.path, 'books', 'book_9', 'b.txt'), 'new book');
    }
    if (withDictionary) {
      write(
        p.join(staging.path, StagedFullRestore.unidicDirName, 'sys.dic'),
        'NEW-DIC',
      );
    }
    write(
      p.join(staging.path, StagedFullRestore.settingsEntryName),
      encodedSettings(),
    );
    write(ready.path, '{"format":1}');
  }

  /// What the native job leaves behind: the archive unpacked into the
  /// device layout plus EXTRACTED, but no READY. The staged database is a
  /// real SQLite file so the boot fix-ups can open it; pass [validDb] false
  /// for one that cannot be opened.
  void seedExtracted({bool validDb = true}) {
    final dbPath = p.join(staging.path, db);
    if (validDb) {
      Directory(staging.path).createSync(recursive: true);
      final raw = sqlite.sqlite3.open(dbPath);
      raw.execute('PRAGMA user_version = ${AppDatabase.latestSchemaVersion}');
      raw.execute(
        'CREATE TABLE books (id INTEGER PRIMARY KEY, file_path TEXT, '
        'cover_image_path TEXT)',
      );
      raw.execute(
        "INSERT INTO books (file_path) VALUES ('/old/files/books/book_9/content')",
      );
      raw.execute(
        'CREATE TABLE server_connections (id INTEGER PRIMARY KEY, '
        'enabled INTEGER NOT NULL DEFAULT 1)',
      );
      raw.execute('INSERT INTO server_connections (id) VALUES (42)');
      raw.close();
    } else {
      write(dbPath, 'not a database');
    }
    write(p.join(staging.path, 'books', 'book_9', 'b.txt'), 'new book');
    write(
      p.join(staging.path, StagedFullRestore.settingsEntryName),
      encodedSettings(),
    );
    write(extracted.path, '{"format":1}');
  }

  /// One boot: apply, then the deferred cleanup.
  Future<StagedRestoreOutcome?> run({
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final restore = StagedFullRestore(
      root: root,
      documentsRoot: documentsRoot,
      prefs: prefs,
      onError: (error, stackTrace) {
        errors.add(error);
        onError?.call(error, stackTrace);
      },
      clearServerSecret: (id) async => clearedSecrets.add(id),
    );
    final outcome = await restore.applyIfStaged();
    await restore.deleteLeftovers();
    return outcome;
  }

  void expectRestoredEndState({bool sqliteDb = false}) {
    if (sqliteDb) {
      expect(
        String.fromCharCodes(File(liveDb.path).readAsBytesSync().take(15)),
        'SQLite format 3',
      );
    } else {
      expect(read(liveDb.path), 'NEW-DB');
    }
    expect(extracted.existsSync(), isFalse);
    expect(liveJournal.existsSync(), isFalse);
    expect(read(p.join(liveBooks.path, 'book_9', 'b.txt')), 'new book');
    expect(Directory(p.join(liveBooks.path, 'book_1')).existsSync(), isFalse);
    expect(staging.existsSync(), isFalse);
    expect(rollback.existsSync(), isFalse);
    expect(prefs.getString('app.theme_mode'), 'dark');
    expect(prefs.getDouble('reader.font_size'), 20.0);
    expect(
      prefs.getString(StagedFullRestore.resultPrefKey),
      StagedFullRestore.resultOk,
    );
  }

  void expectUntouchedEndState() {
    expect(read(liveDb.path), 'OLD-DB');
    expect(read(liveJournal.path), 'OLD-JOURNAL');
    expect(read(p.join(liveBooks.path, 'book_1', 'a.txt')), 'old book');
    expect(Directory(p.join(liveBooks.path, 'book_9')).existsSync(), isFalse);
    expect(prefs.getString('app.theme_mode'), 'light');
    expect(prefs.getInt('ocr.progress.5'), 12);
  }
}
