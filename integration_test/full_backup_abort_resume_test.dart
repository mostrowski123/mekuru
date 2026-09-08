import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/full_backup_it_support.dart';
import 'test_helpers.dart';

/// A job that dies mid-way must pick up where it left off on the next
/// launch, on the device's real filesystem and through the real
/// `ContentResolver` → descriptor → channel path. The abort seam behaves
/// like a process death (nothing is cleaned up); the recovery seam is the
/// production entry point the activity calls on resume.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory tempDir;
  late AppDatabase db;
  late String zipPath;
  late Directory manga;

  /// Checkpoints land every 64 MiB of payload (`ExportJob.CHECKPOINT_BYTES`);
  /// 20 × 4 MiB crosses one, and aborting at 72 MiB leaves work after it.
  const fileCount = 20;
  const fileBytes = 4 << 20;
  const checkpointBytes = 64 << 20;
  const abortAt = 72 << 20;

  Directory jobDir() =>
      Directory(p.join(root.path, StagedFullRestore.jobDirName));
  Directory staging() =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));

  setUp(() async {
    root = await getApplicationSupportDirectory();
    tempDir = await Directory.systemTemp.createTemp('full_backup_resume_');
    zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
    SharedPreferences.setMockInitialValues({});
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    db = AppDatabase();
    manga = await seedBigManga(
      db,
      root,
      files: fileCount,
      sizeBytes: fileBytes,
    );
  });

  tearDown(() async {
    await fullBackupJobs.setForceNonResumableForTest(false);
    await db.close();
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> assertArchiveMatchesLibrary() async {
    final entries = await readZipWithArchive(zipPath);
    final expected = filesUnder(manga);
    final folder = entries.keys
        .firstWhere((n) => n.startsWith('Manga/'))
        .split('/')
        .take(2)
        .join('/');
    for (final MapEntry(key: rel, value: bytes) in expected.entries) {
      expect(entries['$folder/$rel'], bytes, reason: rel);
    }
    expect(
      entries.keys.where((n) => n.startsWith('Manga/')).length,
      expected.length,
    );
  }

  Future<FullBackupJobStatus> exportPausedAt(int bytes) async {
    await fullBackupJobs.abortForTest(afterBytes: bytes);
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    return waitForJob(jobIsPaused, what: 'export to pause');
  }

  testWidgets('an export interrupted mid-archive resumes to a valid zip', (
    tester,
  ) async {
    final paused = await exportPausedAt(abortAt);
    // What the journal promises is the last checkpoint, not the abort point.
    expect(paused.done, greaterThanOrEqualTo(checkpointBytes));
    expect(paused.done, lessThan(fileCount * fileBytes));
    expect(File('$zipPath.partial').existsSync(), isTrue);
    expect(File(zipPath).existsSync(), isFalse);
    expect(File(p.join(jobDir().path, 'job.json')).existsSync(), isTrue);
    expect(File(p.join(jobDir().path, 'journal.jsonl')).existsSync(), isTrue);

    await fullBackupJobs.recoverForTest();
    final done = await waitForJob(jobIsTerminal, what: 'resumed export');
    expect(done.lifecycle, FullBackupJobLifecycle.done);
    expect(done.location, zipPath);
    expect(done.skippedFiles, 0);
    expect(File('$zipPath.partial').existsSync(), isFalse);
    await assertArchiveMatchesLibrary();
  });

  testWidgets('a target that cannot seek starts over and still finishes', (
    tester,
  ) async {
    await fullBackupJobs.setForceNonResumableForTest(true);
    await exportPausedAt(abortAt);

    await fullBackupJobs.recoverForTest();
    final done = await waitForJob(jobIsTerminal, what: 'restarted export');
    expect(done.lifecycle, FullBackupJobLifecycle.done);
    await assertArchiveMatchesLibrary();
  });

  testWidgets('a restore interrupted mid-extraction resumes to EXTRACTED', (
    tester,
  ) async {
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    expect(
      (await waitForJob(jobIsTerminal, what: 'export')).lifecycle,
      FullBackupJobLifecycle.done,
    );
    await fullBackupJobs.consumeResult();

    final service = realFullBackupService(db, root);
    final preview = await service.inspect(FullBackupSource.file(zipPath));
    await fullBackupJobs.abortForTest(afterBytes: abortAt);
    await service.startRestore(preview);
    final paused = await waitForJob(jobIsPaused, what: 'restore to pause');
    expect(paused.kind, FullBackupJobKind.restore);
    expect(paused.done, greaterThanOrEqualTo(checkpointBytes));
    expect(staging().existsSync(), isTrue);
    expect(
      File(
        p.join(staging().path, StagedFullRestore.extractedMarkerName),
      ).existsSync(),
      isFalse,
    );
    final partialFiles = staging()
        .listSync(recursive: true)
        .whereType<File>()
        .length;
    expect(partialFiles, greaterThan(0));

    await fullBackupJobs.recoverForTest();
    final done = await waitForJob(jobIsTerminal, what: 'resumed restore');
    expect(done.lifecycle, FullBackupJobLifecycle.done);
    expect(
      File(
        p.join(staging().path, StagedFullRestore.extractedMarkerName),
      ).existsSync(),
      isTrue,
    );
    final restoredDir = Directory(
      p.join(staging().path, 'books', p.basename(manga.path)),
    );
    final expected = filesUnder(manga);
    final actual = filesUnder(restoredDir);
    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(key: rel, value: bytes) in expected.entries) {
      expect(actual[rel], bytes, reason: rel);
    }
    expect(
      jobDir().existsSync() &&
          File(p.join(jobDir().path, 'job.json')).existsSync(),
      isFalse,
    );
  });

  testWidgets('cancelling a paused export leaves no file and no job', (
    tester,
  ) async {
    await exportPausedAt(abortAt);

    expect(await fullBackupJobs.cancel(), isTrue);
    final cancelled = await waitForJob(jobIsTerminal, what: 'cancel');
    expect(cancelled.lifecycle, FullBackupJobLifecycle.cancelled);
    expect(File('$zipPath.partial').existsSync(), isFalse);
    expect(File(zipPath).existsSync(), isFalse);
    expect(File(p.join(jobDir().path, 'job.json')).existsSync(), isFalse);

    await fullBackupJobs.consumeResult();
    expect(
      (await fullBackupJobs.status()).lifecycle,
      FullBackupJobLifecycle.none,
    );
  });

  testWidgets('cancelling a paused restore leaves no staging', (tester) async {
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    await waitForJob(jobIsTerminal, what: 'export');
    await fullBackupJobs.consumeResult();

    final service = realFullBackupService(db, root);
    final preview = await service.inspect(FullBackupSource.file(zipPath));
    await fullBackupJobs.abortForTest(afterBytes: abortAt);
    await service.startRestore(preview);
    await waitForJob(jobIsPaused, what: 'restore to pause');

    expect(await fullBackupJobs.cancel(), isTrue);
    final cancelled = await waitForJob(jobIsTerminal, what: 'cancel');
    expect(cancelled.lifecycle, FullBackupJobLifecycle.cancelled);
    expect(staging().existsSync(), isFalse);
    await fullBackupJobs.consumeResult();
  });
}
