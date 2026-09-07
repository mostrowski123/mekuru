import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// The boot-time half of a full restore: swap the staged database and books
/// tree into place with same-filesystem renames, then replace preferences.
///
/// Every test drives [StagedFullRestore.applyIfStaged] against a real temp
/// directory laid out like the app-support root. The crash-resume cases
/// pre-arrange the on-disk state a process death would leave behind and
/// assert that the next run converges to the same end state.
void main() {
  late Directory root;
  late SharedPreferences prefs;

  const db = StagedFullRestore.databaseFileName;
  const journal = '$db-journal';

  Directory staging() =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));
  Directory rollback() =>
      Directory(p.join(root.path, StagedFullRestore.rollbackDirName));
  File ready() =>
      File(p.join(staging().path, StagedFullRestore.readyMarkerName));
  Directory liveBooks() =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String read(String path) => File(path).readAsStringSync();

  String encodedSettings() => BackupSerializer.encode(
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

  /// The device before the restore: old DB with a hot journal, one old book.
  void seedLive() {
    write(p.join(root.path, db), 'OLD-DB');
    write(p.join(root.path, journal), 'OLD-JOURNAL');
    write(p.join(liveBooks().path, 'book_1', 'a.txt'), 'old book');
  }

  /// What the import step leaves behind, READY written last.
  void seedStaging({bool withDb = true, bool withBooks = true}) {
    final s = staging();
    if (withDb) write(p.join(s.path, db), 'NEW-DB');
    if (withBooks) {
      write(p.join(s.path, 'books', 'book_9', 'b.txt'), 'new book');
    }
    write(
      p.join(s.path, StagedFullRestore.settingsEntryName),
      encodedSettings(),
    );
    write(ready().path, '{"format":1}');
  }

  Future<StagedRestoreOutcome?> run() async {
    final restore = StagedFullRestore(root: root, prefs: prefs);
    final outcome = await restore.applyIfStaged();
    await restore.deleteLeftovers();
    return outcome;
  }

  void expectRestoredEndState() {
    expect(read(p.join(root.path, db)), 'NEW-DB');
    expect(File(p.join(root.path, journal)).existsSync(), isFalse);
    expect(read(p.join(liveBooks().path, 'book_9', 'b.txt')), 'new book');
    expect(Directory(p.join(liveBooks().path, 'book_1')).existsSync(), isFalse);
    expect(staging().existsSync(), isFalse);
    expect(rollback().existsSync(), isFalse);
    expect(prefs.getString('app.theme_mode'), 'dark');
    expect(prefs.getDouble('reader.font_size'), 20.0);
    expect(prefs.getString(StagedFullRestore.resultPrefKey), 'ok');
  }

  void expectUntouchedEndState() {
    expect(read(p.join(root.path, db)), 'OLD-DB');
    expect(read(p.join(root.path, journal)), 'OLD-JOURNAL');
    expect(read(p.join(liveBooks().path, 'book_1', 'a.txt')), 'old book');
    expect(Directory(p.join(liveBooks().path, 'book_9')).existsSync(), isFalse);
    expect(prefs.getString('app.theme_mode'), 'light');
    expect(prefs.getInt('ocr.progress.5'), 12);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('full_restore_');
    SharedPreferences.setMockInitialValues({
      'app.theme_mode': 'light',
      'ocr.progress.5': 12,
      'ocr.pending_finalizations': '["job-1"]',
      'review_prompt.request_count': 2,
      'backup.last_auto_at': '2026-09-01T00:00:00Z',
    });
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('apply', () {
    test('swaps database and books, replaces prefs, clears markers', () async {
      seedLive();
      seedStaging();

      expect(await run(), StagedRestoreOutcome.applied);

      expectRestoredEndState();
      expect(ready().existsSync(), isFalse);
      // The wipe keeps only device-scoped history; bookId-keyed and
      // scheduler keys must not survive into a library with different ids.
      expect(prefs.containsKey('ocr.progress.5'), isFalse);
      expect(prefs.containsKey('backup.last_auto_at'), isFalse);
      expect(prefs.getString('ocr.pending_finalizations'), '["job-1"]');
      expect(prefs.getInt('review_prompt.request_count'), 2);
      expect(prefs.getString('app.color_theme'), 'mekuruRed');
    });

    test('a device with no library yet still restores', () async {
      write(p.join(root.path, db), 'OLD-DB');
      seedStaging();

      expect(await run(), StagedRestoreOutcome.applied);
      expect(read(p.join(root.path, db)), 'NEW-DB');
      expect(read(p.join(liveBooks().path, 'book_9', 'b.txt')), 'new book');
    });
  });

  group('nothing staged', () {
    test(
      'no READY marker is a no-op that only clears a stale rollback dir',
      () async {
        seedLive();
        write(p.join(rollback().path, db), 'STALE');
        write(p.join(staging().path, 'partial.bin'), 'import in progress');

        expect(await run(), isNull);

        expectUntouchedEndState();
        expect(rollback().existsSync(), isFalse);
        // A READY-less staging dir belongs to an import that may still be
        // running; boot must not delete it under its feet.
        expect(
          File(p.join(staging().path, 'partial.bin')).existsSync(),
          isTrue,
        );
        expect(prefs.containsKey(StagedFullRestore.resultPrefKey), isFalse);
      },
    );
  });

  group('resume after a crash', () {
    test('after only the journal was moved aside', () async {
      seedLive();
      seedStaging();
      // First step done: R exists, old journal already inside it.
      rollback().createSync();
      File(
        p.join(root.path, journal),
      ).renameSync(p.join(rollback().path, journal));

      expect(await run(), StagedRestoreOutcome.applied);
      expectRestoredEndState();
    });

    test('after the database swapped but before the books', () async {
      seedLive();
      seedStaging();
      // Live db is already the new one; old db + journal sit in R.
      rollback().createSync();
      File(p.join(root.path, db)).renameSync(p.join(rollback().path, db));
      File(
        p.join(root.path, journal),
      ).renameSync(p.join(rollback().path, journal));
      File(p.join(staging().path, db)).renameSync(p.join(root.path, db));

      expect(await run(), StagedRestoreOutcome.applied);
      expectRestoredEndState();
    });

    test('after files swapped but before prefs were written', () async {
      seedLive();
      seedStaging();
      rollback().createSync();
      File(p.join(root.path, db)).renameSync(p.join(rollback().path, db));
      File(
        p.join(root.path, journal),
      ).renameSync(p.join(rollback().path, journal));
      File(p.join(staging().path, db)).renameSync(p.join(root.path, db));
      liveBooks().renameSync(p.join(rollback().path, 'books'));
      Directory(p.join(staging().path, 'books')).renameSync(liveBooks().path);

      expect(await run(), StagedRestoreOutcome.applied);
      expectRestoredEndState();
    });

    test('after prefs were written but READY was not deleted', () async {
      seedLive();
      seedStaging();
      rollback().createSync();
      File(p.join(root.path, db)).renameSync(p.join(rollback().path, db));
      File(
        p.join(root.path, journal),
      ).renameSync(p.join(rollback().path, journal));
      File(p.join(staging().path, db)).renameSync(p.join(root.path, db));
      liveBooks().renameSync(p.join(rollback().path, 'books'));
      Directory(p.join(staging().path, 'books')).renameSync(liveBooks().path);
      await prefs.setString('app.theme_mode', 'dark');
      await prefs.setString(StagedFullRestore.resultPrefKey, 'ok');

      expect(await run(), StagedRestoreOutcome.applied);
      expectRestoredEndState();
    });

    test('after READY was deleted the leftovers are just cleaned up', () async {
      // Committed restore: new files live, prefs applied, dirs left behind.
      write(p.join(root.path, db), 'NEW-DB');
      write(p.join(liveBooks().path, 'book_9', 'b.txt'), 'new book');
      write(p.join(rollback().path, db), 'OLD-DB');
      write(p.join(rollback().path, 'books', 'book_1', 'a.txt'), 'old book');
      write(
        p.join(staging().path, StagedFullRestore.settingsEntryName),
        encodedSettings(),
      );
      await prefs.setString('app.theme_mode', 'dark');
      await prefs.setDouble('reader.font_size', 20.0);
      await prefs.setString(StagedFullRestore.resultPrefKey, 'ok');

      expect(await run(), isNull);

      expect(read(p.join(root.path, db)), 'NEW-DB');
      expect(rollback().existsSync(), isFalse);
      expect(prefs.getString(StagedFullRestore.resultPrefKey), 'ok');
    });

    test(
      'after a rollback moved the new db back but not the old one in',
      () async {
        seedLive();
        seedStaging();
        // Interrupted rollback: old db + journal in R, live db slot empty,
        // new db back in S. The retry must simply apply again.
        rollback().createSync();
        File(p.join(root.path, db)).renameSync(p.join(rollback().path, db));
        File(
          p.join(root.path, journal),
        ).renameSync(p.join(rollback().path, journal));

        expect(await run(), StagedRestoreOutcome.applied);
        expectRestoredEndState();
      },
    );
  });

  group('rollback', () {
    test('incomplete staging on the first run changes nothing', () async {
      seedLive();
      seedStaging(withDb: false);

      expect(await run(), StagedRestoreOutcome.rolledBack);

      expectUntouchedEndState();
      expect(ready().existsSync(), isFalse);
      expect(staging().existsSync(), isFalse);
      expect(rollback().existsSync(), isFalse);
      expect(
        prefs.getString(StagedFullRestore.resultPrefKey),
        startsWith('error:'),
      );
    });

    test(
      'a failure after the database swapped restores db and journal',
      () async {
        seedLive();
        seedStaging();
        // R already holds a non-empty books dir, so moving the live books
        // aside fails (ENOTEMPTY) after the database was already swapped.
        write(p.join(rollback().path, 'books', 'junk.txt'), 'junk');

        expect(await run(), StagedRestoreOutcome.rolledBack);

        expectUntouchedEndState();
        expect(ready().existsSync(), isFalse);
        expect(staging().existsSync(), isFalse);
        expect(rollback().existsSync(), isFalse);
        expect(
          prefs.getString(StagedFullRestore.resultPrefKey),
          startsWith('error:'),
        );
      },
    );

    test('reports the failure to the caller', () async {
      seedLive();
      seedStaging(withBooks: false);
      Object? reported;
      final restore = StagedFullRestore(
        root: root,
        prefs: prefs,
        onError: (error, _) => reported = error,
      );

      expect(await restore.applyIfStaged(), StagedRestoreOutcome.rolledBack);
      expect(reported, isNotNull);
    });
  });
}
