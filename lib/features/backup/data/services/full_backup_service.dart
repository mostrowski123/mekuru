import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_plan.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

/// A book import is running, or another job already exists.
class FullBackupBusyException implements Exception {
  const FullBackupBusyException();
}

/// A staged restore is already waiting for a restart; stacking another would
/// mean the boot apply is broken.
class FullBackupPendingRestoreException implements Exception {
  const FullBackupPendingRestoreException();
}

/// The archive has no end record: a copy or download that never finished.
class FullBackupIncompleteException implements Exception {
  const FullBackupIncompleteException();
}

class InsufficientSpaceException implements Exception {
  /// How many more bytes must be free before the operation can run.
  final int neededBytes;
  const InsufficientSpaceException({required this.neededBytes});

  @override
  String toString() => 'Not enough free space: $neededBytes more bytes needed';
}

/// What the confirmation dialogs show before a restore.
class FullBackupPreview {
  final FullBackupManifest manifest;
  final FullBackupSource source;
  final int sizeBytes;
  final int currentBookCount;
  final int currentDictionaryCount;

  const FullBackupPreview({
    required this.manifest,
    required this.source,
    required this.sizeBytes,
    required this.currentBookCount,
    required this.currentDictionaryCount,
  });
}

/// The operations the backup screen drives; [FullBackupService] is the real
/// implementation, tests substitute a fake. Both directions end in a job
/// committed to the Kotlin foreground service; progress and completion are
/// observed through [FullBackupJobApi.status].
abstract interface class FullBackupApi {
  /// Snapshots the database, plans the archive and commits the export job.
  Future<void> prepareExport(FullBackupTarget target);

  Future<FullBackupPreview> inspect(FullBackupSource source);

  /// Commits the restore job for an inspected archive.
  Future<void> startRestore(FullBackupPreview preview);
}

/// Prepares full-backup jobs for the native service (see
/// `FullBackupJobService.kt`): everything the job needs is written under
/// `<root>/full_backup_job/` before `commitJob`, so the service never
/// depends on the Flutter engine again.
class FullBackupService implements FullBackupApi {
  FullBackupService({
    required this.db,
    required this.backupService,
    required this.root,
    required this.appVersion,
    this.documentsRoot,
    this.jobs = const FullBackupJobChannel(),
    this.listTreeFiles = AndroidSafService.listFilesInTreeDir,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final BackupService backupService;

  /// The app-support directory: database, `books/` and the job dir live here.
  final Directory root;

  /// The app-documents directory, home of the downloaded UniDic-lite; null
  /// leaves the dictionary out (tests).
  final Directory? documentsRoot;
  final String appVersion;
  final FullBackupJobApi jobs;

  /// Lists the pages of a manga linked from a folder outside Mekuru.
  final Future<List<SafTreeFile>> Function(String treeUri, String relativePath)
  listTreeFiles;
  final DateTime Function() _clock;

  static const planFileName = 'plan.jsonl';
  static const _sidecarLevel = 6;

  /// Headroom kept free on top of the computed need.
  static const _spaceMargin = 64 * 1024 * 1024;

  Directory get _jobDir =>
      Directory(p.join(root.path, StagedFullRestore.jobDirName));
  Directory get _booksDir =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));
  Directory get _staging =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));

  // ──────────────── Export ────────────────

  @override
  Future<void> prepareExport(FullBackupTarget target) async {
    if (BookRepository.hasImportInFlight) {
      throw const FullBackupBusyException();
    }
    await _requireNoJob();

    // Only our own preparation files are replaced: the directory belongs to
    // the service, and a job that slipped in first keeps its files.
    _jobDir.createSync(recursive: true);
    _deletePrepFiles();
    try {
      final liveDb = File(
        p.join(root.path, StagedFullRestore.databaseFileName),
      );
      final liveDbBytes = liveDb.existsSync() ? liveDb.lengthSync() : 0;
      // The snapshot is the only thing the export writes to local storage.
      await _requireFreeSpace(root, (liveDbBytes * 1.5).ceil());

      final snapshot = File(p.join(_jobDir.path, AppDatabase.databaseFileName));
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);

      final documents = documentsRoot;
      final args = BuildExportPlanArgs(
        snapshotDbPath: snapshot.path,
        booksDirPath: _booksDir.path,
        unidicDirPath: documents == null
            ? null
            : p.join(documents.path, FullBackupManifest.unidicDirName),
      );
      final plan = await Isolate.run(() => buildExportPlan(args));
      final linked = await _linkedPages(plan.linkedManga);
      final payload = [...plan.entries, ...linked.entries];

      final createdAt = _clock().toUtc();
      final manifest = FullBackupManifest(
        format: FullBackupManifest.currentFormat,
        appVersion: appVersion,
        schemaVersion: AppDatabase.latestSchemaVersion,
        createdAt: createdAt,
        appSupportPath: root.path,
        bookCount: plan.bookCount,
        dictionaryCount: plan.dictionaryCount,
        externalMangaCount: linked.mangaCount,
        dbBytes: snapshot.lengthSync(),
        booksBytes: payload.fold(0, (sum, e) => sum + e.size),
        folders: plan.folders,
      );
      final sidecars = [
        _writeSidecar(
          FullBackupManifest.manifestEntry,
          jsonEncode(manifest.toJson()),
        ),
        _writeSidecar(
          FullBackupManifest.readmeEntry,
          fullBackupReadme(appVersion: appVersion, createdAt: createdAt),
        ),
        _writeSidecar(
          FullBackupManifest.settingsEntry,
          BackupSerializer.encode(
            await backupService.createSettingsOnlyManifest(),
          ),
        ),
        _entryFor(snapshot, FullBackupManifest.databaseEntry),
      ];
      final entries = [...sidecars, ...payload];
      File(p.join(_jobDir.path, planFileName)).writeAsStringSync(
        entries.map((e) => '${e.toJsonLine()}\n').join(),
        flush: true,
      );

      final totalBytes = entries.fold(0, (sum, e) => sum + e.size);
      await _commit({
        'kind': 'export',
        'totalBytes': totalBytes,
        ...switch (target) {
          FullBackupTreeTarget(:final treeUri) => {
            'displayName': _exportFileName(createdAt.toLocal()),
            'treeUri': treeUri,
          },
          FullBackupFileTarget(:final path) => {
            'displayName': p.basename(path),
            'targetPath': path,
          },
        },
      });
      logUsage(
        'backup.full_export_started',
        attrs: {
          'books': plan.bookCount,
          'dictionaries': plan.dictionaryCount,
          'size_bucket': _sizeBucket(totalBytes),
        },
      );
    } on FullBackupBusyException {
      // Another job claimed the directory first; leave everything to it.
      rethrow;
    } catch (_) {
      _deletePrepFiles();
      rethrow;
    }
  }

  /// The files [prepareExport] writes before committing.
  List<File> get _prepFiles => [
    for (final name in [
      AppDatabase.databaseFileName,
      FullBackupManifest.manifestEntry,
      FullBackupManifest.readmeEntry,
      FullBackupManifest.settingsFileName,
      planFileName,
    ])
      File(p.join(_jobDir.path, name)),
  ];

  void _deletePrepFiles() {
    for (final file in _prepFiles) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// The page images of manga linked from folders outside Mekuru, read
  /// through the folder grants at export time and filed under
  /// `Manga/<Title>/pages/`. A folder that cannot be listed any more (grant
  /// revoked, card removed) contributes nothing, and that manga stays linked
  /// in the restored library as it always did.
  Future<({List<FullBackupPlanEntry> entries, int mangaCount})> _linkedPages(
    List<LinkedMangaSource> sources,
  ) async {
    // Each listing is a resolve plus a children query on its own thread;
    // a few at a time overlaps them without swamping a slow provider.
    final listings = <List<SafTreeFile>>[];
    for (var i = 0; i < sources.length; i += _listingConcurrency) {
      listings.addAll(
        await Future.wait(
          sources
              .skip(i)
              .take(_listingConcurrency)
              .map((s) => listTreeFiles(s.treeUri, s.imageDirRelativePath)),
        ),
      );
    }

    final entries = <FullBackupPlanEntry>[];
    var mangaCount = 0;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final pages =
          listings[i].where((f) => CbzParser.isImageFile(f.name)).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (pages.isEmpty) continue;
      mangaCount++;
      for (final page in pages) {
        entries.add(
          FullBackupPlanEntry(
            path: page.uri,
            name:
                '${source.prefix}${FullBackupManifest.linkedPagesDirName}/'
                '${page.name}',
            size: math.max(page.size, 0),
            level: 0,
            mtime: page.lastModified,
          ),
        );
      }
    }
    return (entries: entries, mangaCount: mangaCount);
  }

  static const _listingConcurrency = 4;

  FullBackupPlanEntry _writeSidecar(String entryName, String content) {
    final file = File(p.join(_jobDir.path, p.basename(entryName)))
      ..writeAsStringSync(content, flush: true);
    return _entryFor(file, entryName);
  }

  FullBackupPlanEntry _entryFor(File file, String entryName) {
    final stat = file.statSync();
    return FullBackupPlanEntry(
      path: file.path,
      name: entryName,
      size: stat.size,
      level: _sidecarLevel,
      mtime: stat.modified.millisecondsSinceEpoch,
    );
  }

  // ──────────────── Import ────────────────

  /// Reads only the manifest and validates it against this device.
  @override
  Future<FullBackupPreview> inspect(FullBackupSource source) async {
    if (StagedFullRestore.hasStagedRestore(root)) {
      throw const FullBackupPendingRestoreException();
    }
    await _requireNoJob();

    final inspection = await jobs.inspectZip(
      uri: source.uriString,
      name: FullBackupManifest.manifestEntry,
    );
    if (inspection == null || !inspection.isZip) {
      throw const WrongBackupKindException(BackupKind.readingData);
    }
    final text = inspection.text;
    if (text == null) {
      throw const FullBackupFormatException(
        'This zip is not a Mekuru full backup',
      );
    }
    if (inspection.complete == false) {
      throw const FullBackupIncompleteException();
    }
    final FullBackupManifest manifest;
    try {
      manifest = FullBackupManifest.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } on FormatException catch (e) {
      throw FullBackupFormatException('Unreadable manifest: ${e.message}');
    } on TypeError {
      throw const FullBackupFormatException('Unreadable manifest');
    }

    await _requireFreeSpace(root, manifest.totalBytes);

    final counts = await _counts();
    return FullBackupPreview(
      manifest: manifest,
      source: source,
      sizeBytes: source.sizeBytes,
      currentBookCount: counts.books,
      currentDictionaryCount: counts.dictionaries,
    );
  }

  @override
  Future<void> startRestore(FullBackupPreview preview) async {
    await _cancelBackgroundWork();
    final manifest = preview.manifest;
    await _commit({
      'kind': 'restore',
      'sourceUri': preview.source.uriString,
      'stagingPath': _staging.path,
      'totalBytes': manifest.totalBytes,
      'folders': manifest.folders,
      'manifestJson': jsonEncode(manifest.toJson()),
    });
    logUsage(
      'backup.full_restore_started',
      attrs: {
        'books': manifest.bookCount,
        'dictionaries': manifest.dictionaryCount,
        'size_bucket': _sizeBucket(manifest.totalBytes),
      },
    );
  }

  // ──────────────── Helpers ────────────────

  Future<void> _commit(Map<String, Object?> spec) async {
    try {
      await jobs.commitJob(spec);
    } on FullBackupJobBusyException {
      throw const FullBackupBusyException();
    }
  }

  Future<void> _requireNoJob() async {
    final status = await jobs.status();
    if (status.lifecycle != FullBackupJobLifecycle.none) {
      throw const FullBackupBusyException();
    }
  }

  Future<void> _requireFreeSpace(Directory on, int bytes) async {
    final free = await AndroidSafService.getFreeBytes(on.path);
    if (free == null) return; // Unknown: let the write fail loudly instead.
    final needed = bytes + _spaceMargin;
    if (free < needed) {
      throw InsufficientSpaceException(neededBytes: needed - free);
    }
  }

  Future<({int books, int dictionaries})> _counts() async {
    final row = await db
        .customSelect(
          'SELECT (SELECT count(*) FROM books) AS books, '
          '(SELECT count(*) FROM dictionary_metas WHERE is_hidden = 0) '
          'AS dictionaries',
        )
        .getSingle();
    return (
      books: row.read<int>('books'),
      dictionaries: row.read<int>('dictionaries'),
    );
  }

  /// WorkManager can revive the process between `exit(0)` and the user's
  /// relaunch and write OCR results into the old library. Best effort.
  Future<void> _cancelBackgroundWork() async {
    try {
      await Workmanager().cancelAll();
    } catch (_) {
      // No WorkManager here (tests) or nothing scheduled.
    }
  }

  static String _exportFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'mekuru-full-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }

  static String _sizeBucket(int bytes) {
    const mib = 1024 * 1024;
    if (bytes < 100 * mib) return '<100MiB';
    if (bytes < 1024 * mib) return '<1GiB';
    if (bytes < 5 * 1024 * mib) return '<5GiB';
    return '>=5GiB';
  }
}

/// True when the service holds a job or an unread result. Checked in `main`
/// before the first frame so the job page is the first thing on screen.
Future<bool> hasPendingFullBackupJob({
  FullBackupJobApi jobs = const FullBackupJobChannel(),
}) async => (await jobs.status()).lifecycle != FullBackupJobLifecycle.none;
