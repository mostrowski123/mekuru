import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../shared/staged_restore_harness.dart';

/// The boot-time half of a full restore: swap the staged database and books
/// tree into place with same-filesystem renames, then replace preferences.
///
/// Every test drives [StagedFullRestore.applyIfStaged] against a real temp
/// directory laid out like the app-support root. The crash-resume cases
/// pre-arrange the on-disk state a process death would leave behind and
/// assert that the next run converges to the same end state.
void main() {
  late StagedRestoreHarness h;

  const db = StagedRestoreHarness.db;
  const journal = StagedRestoreHarness.journal;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('full_restore_');
    SharedPreferences.setMockInitialValues(
      Map.of(StagedRestoreHarness.initialPrefs),
    );
    h = StagedRestoreHarness(
      root: root,
      prefs: await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async {
    if (await h.root.exists()) await h.root.delete(recursive: true);
  });

  group('apply', () {
    test('swaps database and books, replaces prefs, clears markers', () async {
      h.seedLive();
      h.seedStaging();

      expect(await h.run(), StagedRestoreOutcome.applied);

      h.expectRestoredEndState();
      expect(h.ready.existsSync(), isFalse);
      // The wipe keeps only device-scoped history; bookId-keyed and
      // scheduler keys must not survive into a library with different ids.
      expect(h.prefs.containsKey('ocr.progress.5'), isFalse);
      expect(h.prefs.containsKey('backup.last_auto_at'), isFalse);
      expect(h.prefs.getString('ocr.pending_finalizations'), '["job-1"]');
      expect(h.prefs.getInt('review_prompt.request_count'), 2);
      expect(h.prefs.getString('app.color_theme'), 'mekuruRed');
    });

    test(
      'a staged UniDic-lite replaces the copy in the documents dir',
      () async {
        h.seedLive(withDictionary: true);
        h.seedStaging(withDictionary: true);

        expect(await h.run(), StagedRestoreOutcome.applied);

        h.expectRestoredEndState();
        expect(h.read(h.liveDictionary.path), 'NEW-DIC');
      },
    );

    test(
      'an archive without UniDic-lite leaves the device copy alone',
      () async {
        h.seedLive(withDictionary: true);
        h.seedStaging();

        expect(await h.run(), StagedRestoreOutcome.applied);

        h.expectRestoredEndState();
        expect(h.read(h.liveDictionary.path), 'OLD-DIC');
      },
    );

    test('a device without UniDic-lite gains the staged one', () async {
      h.seedLive();
      h.seedStaging(withDictionary: true);

      expect(await h.run(), StagedRestoreOutcome.applied);

      h.expectRestoredEndState();
      expect(h.read(h.liveDictionary.path), 'NEW-DIC');
    });

    test('a device with no library yet still restores', () async {
      h.write(h.liveDb.path, 'OLD-DB');
      h.seedStaging();

      expect(await h.run(), StagedRestoreOutcome.applied);
      expect(h.read(h.liveDb.path), 'NEW-DB');
      expect(h.read(p.join(h.liveBooks.path, 'book_9', 'b.txt')), 'new book');
    });
  });

  group('nothing staged', () {
    test(
      'no READY marker is a no-op that only clears a stale rollback dir',
      () async {
        h.seedLive();
        h.write(p.join(h.rollback.path, db), 'STALE');
        h.write(p.join(h.staging.path, 'partial.bin'), 'import in progress');

        expect(await h.run(), isNull);

        h.expectUntouchedEndState();
        expect(h.rollback.existsSync(), isFalse);
        // A READY-less staging dir belongs to an import that may still be
        // running; boot must not delete it under its feet.
        expect(
          File(p.join(h.staging.path, 'partial.bin')).existsSync(),
          isTrue,
        );
        expect(h.prefs.containsKey(StagedFullRestore.resultPrefKey), isFalse);
      },
    );
  });

  group('resume after a crash', () {
    test('after only the journal was moved aside', () async {
      h.seedLive();
      h.seedStaging();
      // First step done: R exists, old journal already inside it.
      h.rollback.createSync();
      h.liveJournal.renameSync(p.join(h.rollback.path, journal));

      expect(await h.run(), StagedRestoreOutcome.applied);
      h.expectRestoredEndState();
    });

    test('after the database swapped but before the books', () async {
      h.seedLive();
      h.seedStaging();
      // Live db is already the new one; old db + journal sit in R.
      h.rollback.createSync();
      h.liveDb.renameSync(p.join(h.rollback.path, db));
      h.liveJournal.renameSync(p.join(h.rollback.path, journal));
      File(p.join(h.staging.path, db)).renameSync(h.liveDb.path);

      expect(await h.run(), StagedRestoreOutcome.applied);
      h.expectRestoredEndState();
    });

    test('after files swapped but before prefs were written', () async {
      h.seedLive();
      h.seedStaging();
      h.rollback.createSync();
      h.liveDb.renameSync(p.join(h.rollback.path, db));
      h.liveJournal.renameSync(p.join(h.rollback.path, journal));
      File(p.join(h.staging.path, db)).renameSync(h.liveDb.path);
      h.liveBooks.renameSync(p.join(h.rollback.path, 'books'));
      Directory(p.join(h.staging.path, 'books')).renameSync(h.liveBooks.path);

      expect(await h.run(), StagedRestoreOutcome.applied);
      h.expectRestoredEndState();
    });

    test('after prefs were written but READY was not deleted', () async {
      h.seedLive();
      h.seedStaging();
      h.rollback.createSync();
      h.liveDb.renameSync(p.join(h.rollback.path, db));
      h.liveJournal.renameSync(p.join(h.rollback.path, journal));
      File(p.join(h.staging.path, db)).renameSync(h.liveDb.path);
      h.liveBooks.renameSync(p.join(h.rollback.path, 'books'));
      Directory(p.join(h.staging.path, 'books')).renameSync(h.liveBooks.path);
      await h.prefs.setString('app.theme_mode', 'dark');
      await h.prefs.setString(StagedFullRestore.resultPrefKey, 'ok');

      expect(await h.run(), StagedRestoreOutcome.applied);
      h.expectRestoredEndState();
    });

    test('after READY was deleted the leftovers are just cleaned up', () async {
      // Committed restore: new files live, prefs applied, dirs left behind.
      h.write(h.liveDb.path, 'NEW-DB');
      h.write(p.join(h.liveBooks.path, 'book_9', 'b.txt'), 'new book');
      h.write(p.join(h.rollback.path, db), 'OLD-DB');
      h.write(p.join(h.rollback.path, 'books', 'book_1', 'a.txt'), 'old');
      h.write(
        p.join(h.staging.path, StagedFullRestore.settingsEntryName),
        StagedRestoreHarness.encodedSettings(),
      );
      await h.prefs.setString('app.theme_mode', 'dark');
      await h.prefs.setDouble('reader.font_size', 20.0);
      await h.prefs.setString(StagedFullRestore.resultPrefKey, 'ok');

      expect(await h.run(), isNull);

      expect(h.read(h.liveDb.path), 'NEW-DB');
      expect(h.rollback.existsSync(), isFalse);
      expect(h.prefs.getString(StagedFullRestore.resultPrefKey), 'ok');
    });

    test(
      'after a rollback moved the new db back but not the old one in',
      () async {
        h.seedLive();
        h.seedStaging();
        // Interrupted rollback: old db + journal in R, live db slot empty,
        // new db back in S. The retry must simply apply again.
        h.rollback.createSync();
        h.liveDb.renameSync(p.join(h.rollback.path, db));
        h.liveJournal.renameSync(p.join(h.rollback.path, journal));

        expect(await h.run(), StagedRestoreOutcome.applied);
        h.expectRestoredEndState();
      },
    );
  });

  group('rollback', () {
    test('incomplete staging on the first run changes nothing', () async {
      h.seedLive();
      h.seedStaging(withDb: false);

      expect(await h.run(), StagedRestoreOutcome.rolledBack);

      h.expectUntouchedEndState();
      expect(h.ready.existsSync(), isFalse);
      expect(h.staging.existsSync(), isFalse);
      expect(h.rollback.existsSync(), isFalse);
      expect(
        h.prefs.getString(StagedFullRestore.resultPrefKey),
        startsWith(StagedFullRestore.resultErrorPrefix),
      );
    });

    test(
      'a failure after the database swapped restores db and journal',
      () async {
        h.seedLive();
        h.seedStaging();
        // R already holds a non-empty books dir, so moving the live books
        // aside fails (ENOTEMPTY) after the database was already swapped.
        h.write(p.join(h.rollback.path, 'books', 'junk.txt'), 'junk');

        expect(await h.run(), StagedRestoreOutcome.rolledBack);

        h.expectUntouchedEndState();
        expect(h.ready.existsSync(), isFalse);
        expect(h.staging.existsSync(), isFalse);
        expect(h.rollback.existsSync(), isFalse);
        expect(
          h.prefs.getString(StagedFullRestore.resultPrefKey),
          startsWith(StagedFullRestore.resultErrorPrefix),
        );
      },
    );

    test(
      'a failure after the dictionary swapped restores the old one',
      () async {
        h.seedLive(withDictionary: true);
        h.seedStaging(withDictionary: true);
        // Every swap has happened by the time the settings file is decoded.
        h.write(
          p.join(h.staging.path, StagedFullRestore.settingsEntryName),
          'not a settings file',
        );

        expect(await h.run(), StagedRestoreOutcome.rolledBack);

        h.expectUntouchedEndState();
        expect(h.read(h.liveDictionary.path), 'OLD-DIC');
        expect(h.staging.existsSync(), isFalse);
        expect(h.rollback.existsSync(), isFalse);
      },
    );

    test('a failure on a device without a dictionary leaves none', () async {
      h.seedLive();
      h.seedStaging(withDictionary: true);
      h.write(
        p.join(h.staging.path, StagedFullRestore.settingsEntryName),
        'not a settings file',
      );

      expect(await h.run(), StagedRestoreOutcome.rolledBack);

      h.expectUntouchedEndState();
      expect(h.liveDictionary.existsSync(), isFalse);
    });

    test('reports the failure to the caller', () async {
      h.seedLive();
      h.seedStaging(withBooks: false);
      Object? reported;

      expect(
        await h.run(onError: (error, _) => reported = error),
        StagedRestoreOutcome.rolledBack,
      );
      expect(reported, isNotNull);
    });
  });

  group('extracted by the native job', () {
    test('runs the fix-ups, then applies', () async {
      h.seedLive();
      h.seedExtracted();

      final outcome = await h.run();
      expect(outcome, StagedRestoreOutcome.applied, reason: '${h.errors}');

      h.expectRestoredEndState(sqliteDb: true);
      expect(h.clearedSecrets, [42]);
      final raw = sqlite.sqlite3.open(h.liveDb.path);
      expect(
        raw.select('SELECT file_path FROM books').single['file_path'],
        '${h.root.path}/books/book_9/content',
      );
      expect(
        raw.select('SELECT enabled FROM server_connections').single['enabled'],
        0,
      );
      raw.close();
    });

    test(
      'is left alone while the job that made it is being cancelled',
      () async {
        h.seedLive();
        h.seedExtracted();
        h.write(h.jobCancelled.path, '');

        expect(await h.run(), isNull);

        h.expectUntouchedEndState();
        expect(h.extracted.existsSync(), isTrue);
        expect(h.prefs.containsKey(StagedFullRestore.resultPrefKey), isFalse);
      },
    );

    test(
      'a database that cannot be opened fails before anything moves',
      () async {
        h.seedLive();
        h.seedExtracted(validDb: false);

        expect(await h.run(), StagedRestoreOutcome.rolledBack);

        h.expectUntouchedEndState();
        expect(h.staging.existsSync(), isFalse);
        expect(h.ready.existsSync(), isFalse);
        expect(
          h.prefs.getString(StagedFullRestore.resultPrefKey),
          startsWith(StagedFullRestore.resultErrorPrefix),
        );
      },
    );

    test(
      'a crash between READY and the swap is resumed as a plain apply',
      () async {
        h.seedLive();
        h.seedExtracted();
        h.write(h.ready.path, '{"format":1}');

        expect(await h.run(), StagedRestoreOutcome.applied);
        expect(h.clearedSecrets, isEmpty);
        expect(h.liveJournal.existsSync(), isFalse);
      },
    );

    test('hasWorkUnder and hasStagedRestore see EXTRACTED', () {
      expect(StagedFullRestore.hasWorkUnder(h.root), isFalse);
      h.seedExtracted();
      expect(StagedFullRestore.hasWorkUnder(h.root), isTrue);
      expect(StagedFullRestore.hasStagedRestore(h.root), isTrue);
    });
  });

  group('tombstones', () {
    test('leftovers are retired before deletion and none remain', () async {
      h.seedLive();
      h.seedStaging();

      expect(await h.run(), StagedRestoreOutcome.applied);

      final names = h.root.listSync().map((e) => p.basename(e.path)).toList();
      expect(names, isNot(contains(StagedFullRestore.stagingDirName)));
      expect(names, isNot(contains(StagedFullRestore.rollbackDirName)));
      expect(
        names.where((n) => n.endsWith(StagedFullRestore.tombstoneSuffix)),
        isEmpty,
      );
    });

    test('retire frees the path at once and returns the tombstone', () {
      h.write(p.join(h.staging.path, 'x.txt'), 'x');
      final tombstone = StagedFullRestore.retire(h.staging);
      expect(h.staging.existsSync(), isFalse);
      expect(tombstone, isNotNull);
      expect(tombstone!.path, endsWith(StagedFullRestore.tombstoneSuffix));
      expect(File(p.join(tombstone.path, 'x.txt')).existsSync(), isTrue);
      expect(StagedFullRestore.retire(h.staging), isNull);
    });
  });
}
