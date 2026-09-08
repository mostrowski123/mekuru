import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_database.dart';
import '../../test_app.dart';
import 'fake_full_backup_api.dart';
import 'fake_full_backup_job_api.dart';

void main() {
  final l10n = AppLocalizationsEn();

  late AppDatabase db;
  late FakeFullBackupApi api;
  late FakeFullBackupJobApi jobs;
  late ProviderContainer container;
  late AndroidSafDocument? pickedDocument;
  late int exitCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    api = FakeFullBackupApi();
    jobs = FakeFullBackupJobApi()
      ..current = const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
      );
    pickedDocument = const AndroidSafDocument(
      uri: 'content://doc/picked.zip',
      sizeBytes: 4321,
    );
    exitCalls = 0;
  });

  tearDown(() => db.close());

  /// Lets the job notifier see the job disappear so no poll timer is pending.
  Future<void> settleJob(WidgetTester tester) async {
    jobs.current = FullBackupJobStatus.none;
    await container.read(fullBackupJobProvider.notifier).refresh();
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupHistoryProvider.overrideWith((ref) async => []),
        fullBackupServiceProvider.overrideWith((ref) async => api),
        fullBackupJobApiProvider.overrideWithValue(jobs),
        fullBackupPickersProvider.overrideWithValue(
          FullBackupPickers(
            pickExportTarget: () async =>
                const FullBackupTarget.tree('content://tree/backups'),
            pickSource: () async {
              final document = pickedDocument;
              return document == null
                  ? null
                  : FullBackupSource.uri(
                      document.uri,
                      sizeBytes: document.sizeBytes,
                    );
            },
          ),
        ),
        appExitProvider.overrideWithValue(() async => exitCalls++),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(home: const BackupSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the two kinds as separate, clearly labelled cards', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text(l10n.backupSectionBackup), findsOneWidget);
    expect(find.text(l10n.backupReadingDataBadge), findsOneWidget);
    expect(find.text(l10n.backupImportFileTitle), findsOneWidget);
    expect(find.text(l10n.backupExportTitle), findsOneWidget);

    expect(find.text(l10n.backupFullSectionTitle), findsOneWidget);
    expect(find.text(l10n.backupFullBadge), findsOneWidget);
    expect(find.text(l10n.backupFullExportTitle), findsOneWidget);
    expect(find.text(l10n.backupFullRestoreTitle), findsOneWidget);
    expect(find.text(l10n.backupFullReplacesChip), findsOneWidget);
    expect(find.text(l10n.backupScopeNoteTitle), findsOneWidget);
  });

  testWidgets('export full backup asks for notifications, then hands off', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.backupFullExportTitle));
    await tester.pumpAndSettle();

    expect(jobs.calls, contains('requestNotificationPermission'));
    expect(api.calls, ['prepareExport']);
    expect(api.exportTarget, isA<FullBackupTreeTarget>());
    // The job page (mounted by the app shell, not this screen) takes over.
    expect(
      container.read(fullBackupJobProvider).stage,
      FullBackupJobStage.active,
    );
    expect(find.byType(SnackBar), findsNothing);
    await settleJob(tester);
  });

  testWidgets('a refused export releases the app and explains why', (
    tester,
  ) async {
    api.exportError = const FullBackupBusyException();
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.backupFullExportTitle));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupFullBusy), findsOneWidget);
    expect(container.read(fullBackupJobProvider).blocksApp, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'restore full backup walks review and acknowledgement, then hands off',
    (tester) async {
      await pumpScreen(tester);

      jobs.current = const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
        kind: FullBackupJobKind.restore,
      );
      await tester.tap(find.text(l10n.backupFullRestoreTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.backupFullReviewTitle), findsOneWidget);
      expect(api.calls, ['inspect']);

      await tester.tap(find.text(l10n.backupFullReviewContinue));
      await tester.pumpAndSettle();
      expect(find.text(l10n.backupFullReplaceTitle), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.backupFullReplaceConfirm),
      );
      await tester.pumpAndSettle();

      expect(api.calls, ['inspect', 'startRestore']);
      expect(api.restoredPreview?.source, isA<FullBackupUriSource>());
      expect(
        container.read(fullBackupJobProvider).kind,
        FullBackupJobKind.restore,
      );
      expect(container.read(fullBackupJobProvider).blocksApp, isTrue);
      expect(exitCalls, 0);
      await settleJob(tester);
    },
  );

  testWidgets('cancelling the review never starts a job', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.backupFullRestoreTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(api.calls, ['inspect']);
    expect(jobs.committed, isEmpty);
    expect(container.read(fullBackupJobProvider).blocksApp, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'a .mekuru file picked for a full restore names the other button',
    (tester) async {
      api.inspectError = const WrongBackupKindException(BackupKind.readingData);
      await pumpScreen(tester);

      await tester.tap(find.text(l10n.backupFullRestoreTitle));
      await tester.pumpAndSettle();

      expect(find.text(l10n.backupWrongKindReadingData), findsOneWidget);
      expect(find.text(l10n.backupFullReviewTitle), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
