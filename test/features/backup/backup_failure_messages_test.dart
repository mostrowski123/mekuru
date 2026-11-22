import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/file_pick.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/file_dialog_fakes.dart';
import '../../shared/test_database.dart';
import '../../test_app.dart';
import 'fake_full_backup_api.dart';
import 'fake_full_backup_job_api.dart';

/// A name that must never reach the screen: it stands for a file name or a
/// path inside an exception's text.
const _secret = '秘密の本';

final _failure = Exception('disk full while writing $_secret.mekuru');

final _manifest = BackupManifest(
  version: BackupManifest.currentVersion,
  createdAt: DateTime.utc(2026, 11, 1),
  settings: const BackupSettings(app: {}, reader: {}),
  savedWords: const [],
  books: const [],
);

final _backup = BackupFileInfo(
  filePath: '/backups/manual_$_secret.mekuru',
  fileName: 'manual_$_secret.mekuru',
  createdAt: DateTime(2026, 11, 1),
  sizeBytes: 100,
  isAuto: false,
);

class _BackupService extends BackupService {
  _BackupService(AppDatabase db) : super(db, BookMatchService());

  Object? error;

  @override
  Future<BackupManifest> createBackup() async {
    if (error case final error?) throw error;
    return _manifest;
  }
}

class _FileManager extends BackupFileManager {
  Object? exportError;
  Object? importError;

  @override
  Future<File> createBackupFile(
    BackupManifest manifest, {
    bool isAuto = false,
  }) async => File(_backup.filePath);

  @override
  Future<List<BackupFileInfo>> listBackups() async => [_backup];

  @override
  Future<FileDialogResult<void>> exportBackupFile(String filePath) async {
    if (exportError case final error?) throw error;
    return const FileDialogDone(null);
  }

  @override
  Future<BackupManifest> importBackupFile(String externalPath) async {
    if (importError case final error?) throw error;
    return _manifest;
  }
}

class _RestoreService extends RestoreService {
  _RestoreService(AppDatabase db)
    : super(db, BookMatchService(), PendingBookDataRepository(db));

  @override
  Future<void> applyBookData(int bookId, BackupBookEntry entry) async =>
      throw _failure;
}

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));

  late AppDatabase db;
  late FakeFullBackupApi api;
  late _BackupService backups;
  late _FileManager files;
  late ProviderContainer container;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    api = FakeFullBackupApi();
    backups = _BackupService(db);
    files = _FileManager();
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<List<BackupFileInfo>> Function()? history,
  }) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupServiceProvider.overrideWithValue(backups),
        backupFileManagerProvider.overrideWithValue(files),
        restoreServiceProvider.overrideWithValue(_RestoreService(db)),
        backupHistoryProvider.overrideWith(
          (ref) => (history ?? () async => [_backup])(),
        ),
        fullBackupServiceProvider.overrideWith((ref) async => api),
        fullBackupJobApiProvider.overrideWithValue(
          FakeFullBackupJobApi()
            ..current = const FullBackupJobStatus(
              lifecycle: FullBackupJobLifecycle.running,
            ),
        ),
        fullBackupPickersProvider.overrideWithValue(
          FullBackupPickers(
            pickExportTarget: () async => const FileDialogDone(
              FullBackupTarget.tree('content://tree/backups'),
            ),
            pickSource: () async => const FileDialogDone(
              FullBackupSource.uri('content://doc/picked.zip', sizeBytes: 1),
            ),
          ),
        ),
        appExitProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: const BackupSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// [message] is on screen, and nothing an exception said is.
  void expectOnlyWorded(String message, {String? leaked}) {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining(_secret), findsNothing);
    if (leaked != null) expect(find.textContaining(leaked), findsNothing);
    expect(find.text(message), findsOneWidget);
  }

  void expectLogged(String event) =>
      expect(logs.map((log) => log.$1), contains(event));

  /// Lets the snackbar's timer run out.
  Future<void> finish(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 10));

  Future<void> restoreFromHistory(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ja.commonRestore));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, ja.commonRestore));
    await tester.pumpAndSettle();
  }

  group('a reading data backup', () {
    testWidgets('that cannot be created says so in Japanese', (tester) async {
      backups.error = _failure;
      await pumpScreen(tester);

      await tester.tap(find.text(ja.backupCreateNowTitle));
      await tester.pumpAndSettle();

      expectOnlyWorded(ja.backupNotCreated);
      expectLogged('backup.failed');
      await finish(tester);
    });

    testWidgets('that is created still says so', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(ja.backupCreateNowTitle));
      await tester.pumpAndSettle();

      expect(find.text(ja.backupCreatedSuccess), findsOneWidget);
      await finish(tester);
    });

    testWidgets('that cannot be exported says so in Japanese', (tester) async {
      files.exportError = FileSystemException(
        'Cannot copy file',
        _backup.filePath,
      );
      await pumpScreen(tester);

      await tester.tap(find.text(ja.backupExportTitle));
      await tester.pumpAndSettle();

      expectOnlyWorded(ja.backupExportNotFinished);
      await finish(tester);
    });
  });

  group('a restore from the history', () {
    testWidgets('of a backup from a newer Mekuru asks for an update', (
      tester,
    ) async {
      files.importError = BackupVersionException(9, 1);
      await pumpScreen(tester);

      await restoreFromHistory(tester);

      expectOnlyWorded(ja.backupTooNew, leaked: 'newer version');
      expectLogged('backup.restore_failed');
      await finish(tester);
    });

    testWidgets('of a file that cannot be read asks for another', (
      tester,
    ) async {
      files.importError = BackupFormatException('invalid JSON');
      await pumpScreen(tester);

      await restoreFromHistory(tester);

      expectOnlyWorded(ja.backupFileUnreadable, leaked: 'invalid JSON');
      expectLogged('backup.restore_failed');
      await finish(tester);
    });

    testWidgets('that fails some other way says it did not restore', (
      tester,
    ) async {
      files.importError = _failure;
      await pumpScreen(tester);

      await restoreFromHistory(tester);

      expectOnlyWorded(ja.backupRestoreNotFinished);
      await finish(tester);
    });

    testWidgets('of a full backup still names the other button', (
      tester,
    ) async {
      files.importError = const WrongBackupKindException(BackupKind.full);
      await pumpScreen(tester);

      await restoreFromHistory(tester);

      expect(find.text(ja.backupWrongKindFullBackup), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('books that cannot be updated from a backup say so', (
    tester,
  ) async {
    await pumpScreen(tester);
    final book = (await tester.runAsync(() async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: _secret, filePath: '/b'));
      return (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
    }))!;

    await container.read(restoreNotifierProvider.notifier).applyConflicts([
      BookRestoreConflict(
        existingBook: book,
        backupEntry: const BackupBookEntry(
          bookKey: 'key',
          title: _secret,
          bookType: 'epub',
          readProgress: 0.5,
          bookmarks: [],
          highlights: [],
        ),
      ),
    ]);
    await tester.pumpAndSettle();

    expectOnlyWorded(ja.backupApplyNotFinished);
    await finish(tester);
  });

  group('a full backup', () {
    testWidgets('that cannot start says so in Japanese', (tester) async {
      api.exportError = _failure;
      await pumpScreen(tester);

      await tester.tap(find.text(ja.backupFullExportTitle));
      await tester.pumpAndSettle();

      expectOnlyWorded(ja.backupFullNotStarted);
      expectLogged('backup.full_export_failed');
      await finish(tester);
    });

    testWidgets('restore that cannot start says so in Japanese', (
      tester,
    ) async {
      api.inspectError = _failure;
      await pumpScreen(tester);

      await tester.tap(find.text(ja.backupFullRestoreTitle));
      await tester.pumpAndSettle();

      expectOnlyWorded(ja.backupFullRestoreNotStarted);
      expectLogged('backup.full_restore_failed');
      await finish(tester);
    });
  });

  testWidgets('a history that cannot be listed says so in Japanese', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      history: () async => throw FileSystemException(
        'Directory listing failed',
        '/data/$_secret/backups',
      ),
    );

    expectOnlyWorded(ja.commonLoadFailed);
    expectLogged('backup.history_load_failed');
  });

  testWidgets('a backup file the picker cannot open says so in Japanese', (
    tester,
  ) async {
    fakeFilePicker(
      (_) => throw PlatformException(
        code: 'file_picker_error',
        message: 'Failed to copy $_secret.mekuru',
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.text(ja.backupImportFileTitle));
    await tester.pumpAndSettle();

    expectOnlyWorded(ja.backupFileNotOpened, leaked: 'PlatformException');
    expectLogged('backup.file_open_failed');
    await finish(tester);
  });
}
