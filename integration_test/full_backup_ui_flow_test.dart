import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/backup/presentation/screens/full_backup_job_screen.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/full_backup_it_support.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// The Backup & Restore screen end to end with the REAL service and the REAL
/// native job: only the two system pickers, the notification permission
/// prompt (a system dialog no test can tap) and the process exit are
/// injected, pointing at plain files. Covers both cards, the export behind
/// the job page, the two-step destructive confirmation, the restore job up
/// to "Close Mekuru", and the wrong-kind guard when a `.mekuru` file is
/// picked for a full restore.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory tempDir;
  late String zipPath;
  late FullBackupSource? pickedSource;
  late int exitCalls;

  setUp(() async {
    root = await getApplicationSupportDirectory();
    tempDir = await Directory.systemTemp.createTemp('full_backup_ui_');
    zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
    pickedSource = FullBackupSource.file(zipPath);
    exitCalls = 0;
    SharedPreferences.setMockInitialValues({});
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    // An EXTRACTED marker left behind would replace this device's data on
    // the next real launch.
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// The cards live in a lazy ListView; on a phone-sized viewport the full
  /// backup card is below the fold until scrolled to.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  /// The screen behind the same gate the app shell mounts, so the job page
  /// covers it exactly as it would in the real app.
  Future<AppDatabase> pumpScreen(WidgetTester tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fixturePath = await writeFixtureEpub(tempDir, title: '走れメロス');
    await BookRepository(db).importEpub(fixturePath);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const FullBackupJobGate(child: BackupSettingsScreen()),
        extraOverrides: [
          backupHistoryProvider.overrideWith((ref) async => []),
          fullBackupPickersProvider.overrideWithValue(
            FullBackupPickers(
              pickExportTarget: () async => FullBackupTarget.file(zipPath),
              pickSource: () async => pickedSource,
            ),
          ),
          appExitProvider.overrideWithValue(() async => exitCalls++),
          fullBackupJobApiProvider.overrideWithValue(
            const _NoPermissionPromptChannel(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
    'export behind the job page, then restore through review, acknowledgement, the job page and Close Mekuru',
    (tester) async {
      final l10n = await loadExpectedL10n();
      await pumpScreen(tester);

      // Both kinds are on screen with their own labels.
      expect(find.text(l10n.backupSectionBackup), findsOneWidget);
      await scrollTo(tester, find.text(l10n.backupFullSectionTitle));
      expect(find.text(l10n.backupFullSectionTitle), findsOneWidget);
      await scrollTo(tester, find.text(l10n.backupFullReplacesChip));
      expect(find.text(l10n.backupFullReplacesChip), findsOneWidget);

      // Export: the page covers the screen until Done.
      await scrollTo(tester, find.text(l10n.backupFullExportTitle));
      await tester.tap(find.text(l10n.backupFullExportTitle));
      await pumpUntilVisible(
        tester,
        find.text(l10n.backupFullJobExportTitle),
        timeout: const Duration(seconds: 15),
      );
      expect(
        find.text(l10n.backupFullSectionTitle).hitTestable(),
        findsNothing,
      );
      await pumpUntilVisible(
        tester,
        find.text(l10n.backupFullJobDone),
        timeout: const Duration(seconds: 60),
      );
      expect(File(zipPath).lengthSync(), greaterThan(0));
      await tester.tap(find.text(l10n.backupFullJobDone));
      await pumpUntilGone(tester, find.byType(FullBackupJobScreen));
      // Reaching the export tile scrolled the card's title off the top on a
      // short viewport; bring it back before asking whether it is tappable.
      await scrollTo(tester, find.text(l10n.backupFullSectionTitle));
      expect(
        find.text(l10n.backupFullSectionTitle).hitTestable(),
        findsOneWidget,
      );

      // Restore: review → acknowledge → job page → Close Mekuru → exit.
      await scrollTo(tester, find.text(l10n.backupFullRestoreTitle));
      await tester.tap(find.text(l10n.backupFullRestoreTitle));
      await pumpUntilVisible(tester, find.text(l10n.backupFullReviewTitle));
      expect(find.textContaining('1 book'), findsWidgets);

      await tester.tap(find.text(l10n.backupFullReviewContinue));
      await pumpUntilVisible(tester, find.text(l10n.backupFullReplaceTitle));
      final confirm = find.widgetWithText(
        FilledButton,
        l10n.backupFullReplaceConfirm,
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(confirm);
      await pumpUntilVisible(
        tester,
        find.text(l10n.backupFullJobRestoreTitle),
        timeout: const Duration(seconds: 15),
      );
      await pumpUntilVisible(
        tester,
        find.text(l10n.backupFullRestartButton),
        timeout: const Duration(seconds: 60),
      );
      expect(find.text(l10n.backupFullRestartTitle), findsOneWidget);
      expect(exitCalls, 0);
      final staging = p.join(root.path, StagedFullRestore.stagingDirName);
      expect(
        File(
          p.join(staging, StagedFullRestore.extractedMarkerName),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(staging, StagedFullRestore.databaseFileName)).existsSync(),
        isTrue,
      );
      expect(
        (await fullBackupJobs.status()).lifecycle,
        FullBackupJobLifecycle.done,
      );

      await tester.tap(find.text(l10n.backupFullRestartButton));
      await tester.pump();
      expect(exitCalls, 1);
    },
  );

  testWidgets('cancelling the review never starts a job', (tester) async {
    final l10n = await loadExpectedL10n();
    final db = await pumpScreen(tester);
    // The archive to pick comes from the real service directly; the export
    // UI is already covered above.
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    await waitForJob(jobIsTerminal, what: 'export');
    await fullBackupJobs.consumeResult();
    // The gate saw that job too; let it settle before touching the screen.
    await pumpUntilGone(
      tester,
      find.byType(FullBackupJobScreen),
      timeout: const Duration(seconds: 15),
    );

    await scrollTo(tester, find.text(l10n.backupFullRestoreTitle));
    await tester.tap(find.text(l10n.backupFullRestoreTitle));
    await pumpUntilVisible(tester, find.text(l10n.backupFullReviewTitle));
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(exitCalls, 0);
    expect(find.byType(FullBackupJobScreen), findsNothing);
    expect(
      Directory(
        p.join(root.path, StagedFullRestore.stagingDirName),
      ).existsSync(),
      isFalse,
    );
    expect(
      (await fullBackupJobs.status()).lifecycle,
      FullBackupJobLifecycle.none,
    );
  });

  testWidgets('a .mekuru file picked for a full restore is turned away', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    final mekuruPath = p.join(tempDir.path, 'manual_backup.mekuru');
    File(mekuruPath).writeAsStringSync('{"version":1,"settings":{}}');
    pickedSource = FullBackupSource.file(mekuruPath);
    await pumpScreen(tester);

    await scrollTo(tester, find.text(l10n.backupFullRestoreTitle));
    await tester.tap(find.text(l10n.backupFullRestoreTitle));
    await pumpUntilVisible(
      tester,
      find.text(l10n.backupWrongKindReadingData),
      timeout: const Duration(seconds: 15),
    );
    expect(find.text(l10n.backupFullReviewTitle), findsNothing);
    expect(find.byType(FullBackupJobScreen), findsNothing);
  });
}

/// The real job channel minus the POST_NOTIFICATIONS prompt, which would
/// block the flow behind a system dialog until someone taps it.
class _NoPermissionPromptChannel extends FullBackupJobChannel {
  const _NoPermissionPromptChannel();

  @override
  Future<bool> requestNotificationPermission() async => true;
}
