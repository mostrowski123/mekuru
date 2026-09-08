import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/shared/staged_restore_harness.dart';

/// The boot-time apply is a set of renames whose crash-safety argument rests
/// on filesystem semantics. The unit suite proves the state machine on the
/// host; this proves the two assumptions on the device's real filesystem
/// (ext4/f2fs under app support) and re-runs the two most important
/// scenarios there, in a sandbox root so the live database is never touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StagedRestoreHarness h;

  setUp(() async {
    final appSupport = await getApplicationSupportDirectory();
    final sandbox = Directory(p.join(appSupport.path, 'it_restore_sandbox'));
    await sandbox.create(recursive: true);
    SharedPreferences.setMockInitialValues(
      Map.of(StagedRestoreHarness.initialPrefs),
    );
    h = StagedRestoreHarness(
      root: await sandbox.createTemp('run_'),
      prefs: await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async {
    if (await h.root.exists()) await h.root.delete(recursive: true);
  });

  testWidgets('renaming a directory onto a non-empty one fails here', (
    tester,
  ) async {
    // The rollback path relies on this: a live `books/` that is still in
    // place must make the second move fail instead of merging trees.
    h.write(p.join(h.root.path, 'a', 'x.txt'), 'x');
    h.write(p.join(h.root.path, 'b', 'y.txt'), 'y');

    expect(
      () => Directory(
        p.join(h.root.path, 'a'),
      ).renameSync(p.join(h.root.path, 'b')),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(p.join(h.root.path, 'b', 'y.txt')).existsSync(), isTrue);
    expect(File(p.join(h.root.path, 'a', 'x.txt')).existsSync(), isTrue);
  });

  testWidgets('a same-filesystem directory rename moves the whole tree', (
    tester,
  ) async {
    h.write(p.join(h.liveBooks.path, 'book_1', 'deep', 'page.png'), 'png');
    h.rollback.createSync();

    h.liveBooks.renameSync(p.join(h.rollback.path, 'books'));

    expect(
      h.read(p.join(h.rollback.path, 'books', 'book_1', 'deep', 'page.png')),
      'png',
    );
    expect(h.liveBooks.existsSync(), isFalse);
  });

  testWidgets('resumes after a crash between the database and books swap', (
    tester,
  ) async {
    h.seedLive();
    h.seedStaging();
    h.rollback.createSync();
    h.liveDb.renameSync(p.join(h.rollback.path, StagedRestoreHarness.db));
    h.liveJournal.renameSync(
      p.join(h.rollback.path, StagedRestoreHarness.journal),
    );
    File(
      p.join(h.staging.path, StagedRestoreHarness.db),
    ).renameSync(h.liveDb.path);

    expect(await h.run(), StagedRestoreOutcome.applied);
    h.expectRestoredEndState();
  });

  testWidgets('rolls back database and journal when the books swap fails', (
    tester,
  ) async {
    h.seedLive();
    h.seedStaging();
    h.write(p.join(h.rollback.path, 'books', 'junk.txt'), 'junk');

    expect(await h.run(), StagedRestoreOutcome.rolledBack);

    h.expectUntouchedEndState();
    expect(
      h.prefs.getString(StagedFullRestore.resultPrefKey),
      startsWith(StagedFullRestore.resultErrorPrefix),
    );
    expect(h.staging.existsSync(), isFalse);
    expect(h.rollback.existsSync(), isFalse);
  });

  testWidgets('EXTRACTED is prepared and applied on the device filesystem', (
    tester,
  ) async {
    h.seedLive();
    h.seedExtracted();

    final outcome = await h.run();
    expect(outcome, StagedRestoreOutcome.applied, reason: '${h.errors}');
    h.expectRestoredEndState(sqliteDb: true);
    expect(h.clearedSecrets, [42]);
  });

  testWidgets('retiring a directory frees its path at once', (tester) async {
    h.write(p.join(h.rollback.path, 'books', 'old.bin'), 'old');

    final tombstone = StagedFullRestore.retire(h.rollback);

    expect(h.rollback.existsSync(), isFalse);
    expect(tombstone, isNotNull);
    expect(
      File(p.join(tombstone!.path, 'books', 'old.bin')).existsSync(),
      isTrue,
    );
    // The path is free for the next job while the old tree is still there.
    h.rollback.createSync();
    expect(h.rollback.listSync(), isEmpty);
  });
}
