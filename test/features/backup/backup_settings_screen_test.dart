import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_database.dart';
import '../../test_app.dart';
import 'fake_full_backup_api.dart';

/// Returns whatever file the test scripted, standing in for the system
/// picker behind `BackupFileManager.pickBackupFile`.
class _FakeFilePicker extends FilePickerPlatform {
  PlatformFile? file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final picked = file;
    return picked == null ? null : FilePickerResult([picked]);
  }
}

void main() {
  final l10n = AppLocalizationsEn();

  late AppDatabase db;
  late FakeFullBackupApi api;
  late AndroidSafDocument? pickedDocument;
  late int exitCalls;
  late _FakeFilePicker filePicker;
  late FilePickerPlatform originalFilePicker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    api = FakeFullBackupApi();
    pickedDocument = const AndroidSafDocument(
      uri: 'content://doc/picked.zip',
      displayName: 'mekuru-full-backup.zip',
      sizeBytes: 4321,
    );
    exitCalls = 0;
    originalFilePicker = FilePickerPlatform.instance;
    filePicker = _FakeFilePicker();
    FilePickerPlatform.instance = filePicker;
  });

  tearDown(() async {
    FilePickerPlatform.instance = originalFilePicker;
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backupHistoryProvider.overrideWith((ref) async => []),
          fullBackupServiceProvider.overrideWith((ref) async => api),
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
                        displayName: document.displayName,
                      );
              },
            ),
          ),
          appExitProvider.overrideWithValue(() async => exitCalls++),
        ],
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

  testWidgets('export full backup reports the saved size', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.backupFullExportTitle));
    await tester.pumpAndSettle();

    expect(api.calls, ['export']);
    expect(find.text(l10n.backupFullExported(size: '777 B')), findsOneWidget);
    // Let the snackbar and the success auto-dismiss timers run out.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'restore full backup walks review, acknowledgement, staging and exit',
    (tester) async {
      await pumpScreen(tester);

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

      expect(api.calls, ['inspect', 'stage']);
      expect(find.text(l10n.backupFullRestartTitle), findsOneWidget);
      expect(exitCalls, 0);

      await tester.tap(find.text(l10n.backupFullRestartButton));
      await tester.pumpAndSettle();
      expect(exitCalls, 1);
    },
  );

  testWidgets('cancelling the review never stages or exits', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.backupFullRestoreTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(api.calls, ['inspect']);
    expect(exitCalls, 0);
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

  testWidgets(
    'a .zip picked for a reading data import names the other button',
    (tester) async {
      filePicker.file = PlatformFile(
        name: 'mekuru-full-backup.zip',
        size: 4,
        path: '/picked/mekuru-full-backup.zip',
      );
      await pumpScreen(tester);

      await tester.tap(find.text(l10n.backupImportFileTitle));
      await tester.pumpAndSettle();

      expect(find.text(l10n.backupWrongKindFullBackup), findsOneWidget);
      expect(find.text(l10n.backupRestoreDialogTitle), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
