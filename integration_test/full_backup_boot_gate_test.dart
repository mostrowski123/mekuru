import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/backup/presentation/screens/full_backup_job_screen.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/full_backup_it_support.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// A launch that finds a job (or its unread result) on disk shows the job
/// page as its first frame, keeps the app unreachable behind it, and only
/// reveals the app once the outcome is acknowledged. `hasPendingFullBackupJob`
/// is the real boot check; the real `MekuruApp` shell does the rest.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory tempDir;
  late AppDatabase db;
  late String zipPath;

  setUp(() async {
    root = await getApplicationSupportDirectory();
    tempDir = await Directory.systemTemp.createTemp('full_backup_boot_');
    zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
    SharedPreferences.setMockInitialValues({});
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> bootRealApp(WidgetTester tester) async {
    final pending = await hasPendingFullBackupJob();
    expect(pending, isTrue, reason: 'main would not have blocked the app');
    await tester.pumpWidget(
      buildIntegrationTestRealApp(
        db: db,
        extraOverrides: [
          initialFullBackupJobPendingProvider.overrideWithValue(pending),
        ],
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a paused job blocks the app from the first frame, swallows Back, resumes, and Done reveals the app',
    (tester) async {
      final l10n = await loadExpectedL10n();
      await seedBigManga(db, root, files: 8, sizeBytes: 4 << 20);
      await fullBackupJobs.abortForTest(afterBytes: 6 << 20);
      await realFullBackupService(
        db,
        root,
      ).prepareExport(FullBackupTarget.file(zipPath));
      await waitForJob(jobIsPaused, what: 'export to pause');

      await bootRealApp(tester);
      expect(find.byType(FullBackupJobScreen), findsOneWidget);
      expect(find.text(l10n.backupFullJobExportTitle), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Back must not leave the page.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(FullBackupJobScreen), findsOneWidget);

      // What the activity does on resume: pick the job back up.
      await fullBackupJobs.recoverForTest();
      await pumpUntilVisible(
        tester,
        find.text(l10n.backupFullJobDone),
        timeout: const Duration(seconds: 90),
      );
      expect(File(zipPath).existsSync(), isTrue);

      await tester.tap(find.text(l10n.backupFullJobDone));
      await pumpUntilVisible(
        tester,
        find.byType(NavigationBar),
        timeout: const Duration(seconds: 15),
      );
      expect(find.byType(FullBackupJobScreen), findsNothing);
      expect(await hasPendingFullBackupJob(), isFalse);
    },
  );

  testWidgets('a result left while the app was away is shown at launch', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    await seedBigManga(db, root, files: 1, sizeBytes: 1 << 20);
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    await waitForJob(jobIsDone, what: 'export');

    // The same gate the shell mounts, seeded the way main seeds it.
    final pending = await hasPendingFullBackupJob();
    expect(pending, isTrue);
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const FullBackupJobGate(
          child: Scaffold(body: Center(child: Text('the app'))),
        ),
        extraOverrides: [
          initialFullBackupJobPendingProvider.overrideWithValue(pending),
        ],
      ),
    );
    await pumpUntilVisible(
      tester,
      find.textContaining(
        l10n.backupFullExported(size: '\u0000').split('\u0000').first,
      ),
      timeout: const Duration(seconds: 15),
    );
    expect(find.text('the app'), findsNothing);

    await tester.tap(find.text(l10n.backupFullJobDone));
    await pumpUntilVisible(tester, find.text('the app'));
    expect(
      (await fullBackupJobs.status()).lifecycle,
      FullBackupJobLifecycle.none,
    );
  });

  testWidgets(
    'a staging dir left by a cancelled job is never applied at boot',
    (tester) async {
      final liveDb = File(
        p.join(root.path, StagedFullRestore.databaseFileName),
      );
      await db.close();
      final before = liveDb.readAsBytesSync();
      final staging = Directory(
        p.join(root.path, StagedFullRestore.stagingDirName),
      )..createSync(recursive: true);
      File(
        p.join(staging.path, StagedFullRestore.extractedMarkerName),
      ).writeAsStringSync('{}');
      File(p.join(staging.path, 'half.bin')).writeAsStringSync('x');
      File(
          p.join(
            root.path,
            StagedFullRestore.jobDirName,
            StagedFullRestore.cancelledMarkerName,
          ),
        )
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');

      await applyStagedFullRestoreIfAny();

      expect(liveDb.readAsBytesSync(), before);
      expect(File(p.join(staging.path, 'half.bin')).existsSync(), isTrue);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          StagedFullRestore.resultPrefKey,
        ),
        isFalse,
      );
      db = AppDatabase();
    },
  );
}
