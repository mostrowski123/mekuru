import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/prepare_staged_restore.dart';

/// Scriptable stand-in for [FullBackupService] so notifier and screen tests
/// run without SAF, a database snapshot or a process exit.
class FakeFullBackupApi implements FullBackupApi {
  final calls = <String>[];
  FullBackupTarget? exportTarget;
  FullBackupSource? inspectedSource;
  FullBackupSource? stagedSource;
  Object? exportError;
  Object? inspectError;
  Object? stageError;
  List<(int, int)> progressToEmit = const [];
  int exportedBytes = 777;
  int skippedFiles = 0;
  int currentBookCount = 2;
  int currentDictionaryCount = 1;

  static final manifest = FullBackupManifest(
    format: 1,
    appVersion: '1.37.0',
    schemaVersion: AppDatabase.latestSchemaVersion,
    createdAt: DateTime.utc(2026, 9, 1),
    appSupportPath: '/old',
    bookCount: 7,
    dictionaryCount: 3,
    externalMangaCount: 0,
    dbBytes: 1000,
    booksBytes: 4000,
    entryCount: 20,
  );

  @override
  Future<FullBackupExportResult> export(
    FullBackupTarget target, {
    FullBackupProgress? onProgress,
  }) async {
    calls.add('export');
    exportTarget = target;
    for (final (done, total) in progressToEmit) {
      onProgress?.call(done, total);
    }
    if (exportError != null) throw exportError!;
    return FullBackupExportResult(
      location: 'content://tree/doc.zip',
      bytes: exportedBytes,
      entries: 20,
      skippedFiles: skippedFiles,
      manifest: manifest,
    );
  }

  @override
  Future<FullBackupPreview> inspect(FullBackupSource source) async {
    calls.add('inspect');
    inspectedSource = source;
    if (inspectError != null) throw inspectError!;
    return FullBackupPreview(
      manifest: manifest,
      sizeBytes: source.sizeBytes,
      currentBookCount: currentBookCount,
      currentDictionaryCount: currentDictionaryCount,
    );
  }

  @override
  Future<PreparedStagedRestore> stage(
    FullBackupSource source, {
    FullBackupProgress? onProgress,
  }) async {
    calls.add('stage');
    stagedSource = source;
    for (final (done, total) in progressToEmit) {
      onProgress?.call(done, total);
    }
    if (stageError != null) throw stageError!;
    return const PreparedStagedRestore(
      serverConnectionIds: [],
      rewrittenBooks: 0,
      rewrittenCaches: 0,
    );
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
  }
}
