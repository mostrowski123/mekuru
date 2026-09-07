import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// The Backup & Restore screen end to end with the REAL service and the REAL
/// native archiver: only the two system pickers and the process exit are
/// injected, pointing at plain files. Covers both cards, the export, the
/// two-step destructive confirmation, staging, the closing dialog, and the
/// wrong-kind guard when a `.mekuru` file is picked for a full restore.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory tempDir;
  late String zipPath;
  late FullBackupSource? pickedSource;
  late int exitCalls;

  Future<void> wipeStaging() async {
    for (final name in [
      StagedFullRestore.stagingDirName,
      StagedFullRestore.rollbackDirName,
    ]) {
      final dir = Directory(p.join(root.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  setUp(() async {
    root = await getApplicationSupportDirectory();
    tempDir = await Directory.systemTemp.createTemp('full_backup_ui_');
    zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
    pickedSource = FullBackupSource.file(zipPath);
    exitCalls = 0;
    SharedPreferences.setMockInitialValues({});
    await cleanupAppBooksDir();
    await wipeStaging();
  });

  tearDown(() async {
    // A READY marker left behind would replace this device's data on the
    // next real launch.
    await wipeStaging();
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

  Future<AppDatabase> pumpScreen(WidgetTester tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fixturePath = await writeFixtureEpub(tempDir, title: '走れメロス');
    await BookRepository(db).importEpub(fixturePath);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const BackupSettingsScreen(),
        extraOverrides: [
          backupHistoryProvider.overrideWith((ref) async => []),
          fullBackupPickersProvider.overrideWithValue(
            FullBackupPickers(
              pickExportTarget: () async => FullBackupTarget.file(zipPath),
              pickSource: () async => pickedSource,
            ),
          ),
          appExitProvider.overrideWithValue(() async => exitCalls++),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
    'export, then restore through review, acknowledgement, staging and the closing dialog',
    (tester) async {
      final l10n = await loadExpectedL10n();
      await pumpScreen(tester);

      // Both kinds are on screen with their own labels.
      expect(find.text(l10n.backupSectionBackup), findsOneWidget);
      await scrollTo(tester, find.text(l10n.backupFullSectionTitle));
      expect(find.text(l10n.backupFullSectionTitle), findsOneWidget);
      await scrollTo(tester, find.text(l10n.backupFullReplacesChip));
      expect(find.text(l10n.backupFullReplacesChip), findsOneWidget);

      // Export through the real service and the native zip writer.
      await scrollTo(tester, find.text(l10n.backupFullExportTitle));
      await tester.tap(find.text(l10n.backupFullExportTitle));
      await pumpUntilVisible(
        tester,
        find.textContaining('Full backup saved'),
        timeout: const Duration(seconds: 30),
      );
      expect(File(zipPath).lengthSync(), greaterThan(0));
      await pumpUntilGone(
        tester,
        find.textContaining('Full backup saved'),
        timeout: const Duration(seconds: 15),
      );

      // Restore: review → acknowledge → stage → closing dialog → exit.
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
        find.text(l10n.backupFullRestartTitle),
        timeout: const Duration(seconds: 30),
      );
      expect(exitCalls, 0);
      expect(
        File(
          p.join(
            root.path,
            StagedFullRestore.stagingDirName,
            StagedFullRestore.readyMarkerName,
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(
            root.path,
            StagedFullRestore.stagingDirName,
            StagedFullRestore.databaseFileName,
          ),
        ).existsSync(),
        isTrue,
      );

      await tester.tap(find.text(l10n.backupFullRestartButton));
      await tester.pumpAndSettle();
      expect(exitCalls, 1);
    },
  );

  testWidgets('cancelling the review leaves nothing staged', (tester) async {
    final l10n = await loadExpectedL10n();
    final db = await pumpScreen(tester);
    // The archive to pick comes from the real service directly; the export
    // UI is already covered above.
    await tester.runAsync(() async {
      final service = FullBackupService(
        db: db,
        backupService: BackupService(db, BookMatchService()),
        root: root,
        cacheDir: await getTemporaryDirectory(),
        appVersion: 'integration',
      );
      await service.export(FullBackupTarget.file(zipPath));
    });

    await scrollTo(tester, find.text(l10n.backupFullRestoreTitle));
    await tester.tap(find.text(l10n.backupFullRestoreTitle));
    await pumpUntilVisible(tester, find.text(l10n.backupFullReviewTitle));
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(exitCalls, 0);
    expect(
      Directory(
        p.join(root.path, StagedFullRestore.stagingDirName),
      ).existsSync(),
      isFalse,
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
  });
}
