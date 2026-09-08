import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';

/// Scriptable stand-in for [FullBackupService] so notifier and screen tests
/// run without SAF, a database snapshot or the native job service.
class FakeFullBackupApi implements FullBackupApi {
  final calls = <String>[];
  FullBackupTarget? exportTarget;
  FullBackupSource? inspectedSource;
  FullBackupPreview? restoredPreview;
  Object? exportError;
  Object? inspectError;
  Object? restoreError;
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
    folders: const {'Books/走れメロス/': 'book_1_aaaaaaaa'},
  );

  @override
  Future<void> prepareExport(FullBackupTarget target) async {
    calls.add('prepareExport');
    exportTarget = target;
    if (exportError != null) throw exportError!;
  }

  @override
  Future<FullBackupPreview> inspect(FullBackupSource source) async {
    calls.add('inspect');
    inspectedSource = source;
    if (inspectError != null) throw inspectError!;
    return FullBackupPreview(
      manifest: manifest,
      source: source,
      sizeBytes: source.sizeBytes,
      currentBookCount: currentBookCount,
      currentDictionaryCount: currentDictionaryCount,
    );
  }

  @override
  Future<void> startRestore(FullBackupPreview preview) async {
    calls.add('startRestore');
    restoredPreview = preview;
    if (restoreError != null) throw restoreError!;
  }
}
