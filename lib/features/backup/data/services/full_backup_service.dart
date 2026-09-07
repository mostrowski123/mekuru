import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/prepare_staged_restore.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

/// A book import is running; its directory would be half-written in the zip.
class FullBackupBusyException implements Exception {
  const FullBackupBusyException();
}

/// The operation was cancelled by the user.
class FullBackupCancelledException implements Exception {
  const FullBackupCancelledException();
}

/// A staged restore is already waiting for a restart; stacking another would
/// mean the boot apply is broken.
class FullBackupPendingRestoreException implements Exception {
  const FullBackupPendingRestoreException();
}

class InsufficientSpaceException implements Exception {
  /// How many more bytes must be free before the operation can run.
  final int neededBytes;
  const InsufficientSpaceException({required this.neededBytes});

  @override
  String toString() => 'Not enough free space: $neededBytes more bytes needed';
}

class FullBackupExportResult {
  final String location;
  final int bytes;
  final int entries;
  final int skippedFiles;
  final FullBackupManifest manifest;

  const FullBackupExportResult({
    required this.location,
    required this.bytes,
    required this.entries,
    required this.skippedFiles,
    required this.manifest,
  });
}

/// What the confirmation dialogs show before a restore.
class FullBackupPreview {
  final FullBackupManifest manifest;
  final int sizeBytes;
  final int currentBookCount;
  final int currentDictionaryCount;

  const FullBackupPreview({
    required this.manifest,
    required this.sizeBytes,
    required this.currentBookCount,
    required this.currentDictionaryCount,
  });
}

typedef FullBackupProgress = void Function(int done, int total);

/// The operations the backup screen drives; [FullBackupService] is the real
/// implementation, tests substitute a fake.
abstract interface class FullBackupApi {
  Future<FullBackupExportResult> export(
    FullBackupTarget target, {
    FullBackupProgress? onProgress,
  });

  Future<FullBackupPreview> inspect(FullBackupSource source);

  Future<PreparedStagedRestore> stage(
    FullBackupSource source, {
    FullBackupProgress? onProgress,
  });

  Future<void> cancel();
}

/// Orchestrates full backups: snapshot the database, write the sidecar
/// files, and drive the native streaming zip (see `FullBackupArchive.kt`).
///
/// Export never holds more than the database snapshot in cache. Import
/// extracts into `<root>/restore_staging/`, fixes it up there, and leaves a
/// READY marker for [StagedFullRestore] to apply on the next cold start.
class FullBackupService implements FullBackupApi {
  FullBackupService({
    required this.db,
    required this.backupService,
    required this.root,
    required this.cacheDir,
    required this.appVersion,
    Future<void> Function(int connectionId)? clearServerSecret,
    DateTime Function()? clock,
  }) : _clearServerSecret = clearServerSecret ?? ServerSecretStorage().clear,
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final BackupService backupService;

  /// The app-support directory: database and `books/` live here.
  final Directory root;
  final Directory cacheDir;
  final String appVersion;
  final Future<void> Function(int connectionId) _clearServerSecret;
  final DateTime Function() _clock;

  static const exportDirName = 'full_backup_export';
  static const excludedDirNames = ['.trash'];
  static const _sidecarLevel = 6;

  /// Headroom kept free on top of the computed need.
  static const _spaceMargin = 64 * 1024 * 1024;

  Directory get _booksDir =>
      Directory(p.join(root.path, StagedFullRestore.booksDirName));
  Directory get _staging =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));

  // ──────────────── Export ────────────────

  @override
  Future<FullBackupExportResult> export(
    FullBackupTarget target, {
    FullBackupProgress? onProgress,
  }) => tracedOperation(
    'backup.full_export_duration_ms',
    action: () => _export(target, onProgress),
  );

  Future<FullBackupExportResult> _export(
    FullBackupTarget target,
    FullBackupProgress? onProgress,
  ) async {
    if (BookRepository.hasImportInFlight) {
      throw const FullBackupBusyException();
    }
    final exportDir = Directory(p.join(cacheDir.path, exportDirName));
    if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
    exportDir.createSync(recursive: true);
    try {
      final liveDb = File(
        p.join(root.path, StagedFullRestore.databaseFileName),
      );
      final liveDbBytes = liveDb.existsSync() ? liveDb.lengthSync() : 0;
      final measured =
          await AndroidSafService.measureTree(
            _booksDir.path,
            excludeDirNames: excludedDirNames,
          ) ??
          (bytes: 0, files: 0);
      // The snapshot is the only thing written to local storage.
      await _requireFreeSpace(cacheDir, (liveDbBytes * 1.5).ceil());

      final snapshot = File(
        p.join(exportDir.path, FullBackupManifest.databaseEntry),
      );
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);

      final counts = await _counts();
      final manifest = FullBackupManifest(
        format: FullBackupManifest.currentFormat,
        appVersion: appVersion,
        schemaVersion: AppDatabase.latestSchemaVersion,
        createdAt: _clock().toUtc(),
        appSupportPath: root.path,
        bookCount: counts.books,
        dictionaryCount: counts.dictionaries,
        externalMangaCount: counts.external,
        dbBytes: snapshot.lengthSync(),
        booksBytes: measured.bytes,
        entryCount: measured.files + 3,
      );
      final manifestFile = File(
        p.join(exportDir.path, FullBackupManifest.manifestEntry),
      )..writeAsStringSync(jsonEncode(manifest.toJson()));
      final settingsFile =
          File(p.join(exportDir.path, FullBackupManifest.settingsEntry))
            ..writeAsStringSync(
              BackupSerializer.encode(
                await backupService.createSettingsOnlyManifest(),
              ),
            );

      final files = [
        ZipFileEntry(
          manifestFile.path,
          FullBackupManifest.manifestEntry,
          _sidecarLevel,
        ),
        ZipFileEntry(
          settingsFile.path,
          FullBackupManifest.settingsEntry,
          _sidecarLevel,
        ),
        ZipFileEntry(
          snapshot.path,
          FullBackupManifest.databaseEntry,
          _sidecarLevel,
        ),
      ];
      final roots = [ZipRoot(_booksDir.path, FullBackupManifest.booksPrefix)];

      final result = await _withProgress(onProgress, () {
        return switch (target) {
          FullBackupFileTarget(:final path) => AndroidSafService.writeZipToFile(
            path: path,
            roots: roots,
            files: files,
            excludeDirNames: excludedDirNames,
          ),
          FullBackupTreeTarget(:final treeUri) =>
            AndroidSafService.writeZipToTree(
              treeUri: treeUri,
              displayName: _exportFileName(),
              roots: roots,
              files: files,
              excludeDirNames: excludedDirNames,
            ),
        };
      });
      if (result.cancelled) throw const FullBackupCancelledException();

      logUsage(
        'backup.full_export',
        attrs: {
          'books': counts.books,
          'dictionaries': counts.dictionaries,
          'size_bucket': _sizeBucket(result.bytes),
          'skipped_files': result.skippedFiles,
        },
      );
      return FullBackupExportResult(
        location: result.location,
        bytes: result.bytes,
        entries: result.entries,
        skippedFiles: result.skippedFiles,
        manifest: manifest,
      );
    } finally {
      if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
    }
  }

  // ──────────────── Import ────────────────

  /// Reads only the manifest and validates it against this device.
  @override
  Future<FullBackupPreview> inspect(FullBackupSource source) async {
    if (File(
      p.join(_staging.path, StagedFullRestore.readyMarkerName),
    ).existsSync()) {
      throw const FullBackupPendingRestoreException();
    }

    final peek = await AndroidSafService.peekZipEntryText(
      uri: source is FullBackupUriSource ? source.uri : null,
      path: source is FullBackupFileSource ? source.path : null,
      name: FullBackupManifest.manifestEntry,
    );
    if (peek == null || !peek.isZip) {
      throw const WrongBackupKindException(BackupKind.readingData);
    }
    final text = peek.text;
    if (text == null) {
      throw const FullBackupFormatException(
        'This zip is not a Mekuru full backup',
      );
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
      sizeBytes: source.sizeBytes,
      currentBookCount: counts.books,
      currentDictionaryCount: counts.dictionaries,
    );
  }

  /// Extracts and prepares the archive for the boot-time apply. On return
  /// the READY marker exists and the app must exit; on failure nothing on the
  /// live device has changed and the staging directory is gone.
  @override
  Future<PreparedStagedRestore> stage(
    FullBackupSource source, {
    FullBackupProgress? onProgress,
  }) => tracedOperation(
    'backup.full_restore_stage_duration_ms',
    action: () => _stage(source, onProgress),
  );

  Future<PreparedStagedRestore> _stage(
    FullBackupSource source,
    FullBackupProgress? onProgress,
  ) async {
    await _cancelBackgroundWork();
    final rollback = Directory(
      p.join(root.path, StagedFullRestore.rollbackDirName),
    );
    for (final dir in [_staging, rollback]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
    _staging.createSync(recursive: true);
    try {
      final entries = await _withProgress(onProgress, () {
        return switch (source) {
          FullBackupFileSource(:final path) =>
            AndroidSafService.extractZipFromFile(
              path: path,
              destPath: _staging.path,
            ),
          FullBackupUriSource(:final uri) =>
            AndroidSafService.extractZipFromUri(
              uri: uri,
              destPath: _staging.path,
            ),
        };
      });
      if (entries == null) throw const FullBackupCancelledException();

      final manifestFile = File(
        p.join(_staging.path, FullBackupManifest.manifestEntry),
      );
      final prepared = await compute(
        prepareStagedRestore,
        PrepareStagedRestoreArgs(
          stagingPath: _staging.path,
          rootPath: root.path,
          manifestJson: manifestFile.existsSync()
              ? manifestFile.readAsStringSync()
              : '{}',
        ),
      );
      // Secrets are keyed by connection id; the restored ids can collide
      // with this device's old connections, so never let a stale secret
      // pair with a restored URL.
      for (final id in prepared.serverConnectionIds) {
        await _clearServerSecret(id);
      }
      logUsage(
        'backup.full_restore_staged',
        attrs: {
          'entries': entries,
          'rewritten_books': prepared.rewrittenBooks,
          'rewritten_caches': prepared.rewrittenCaches,
        },
      );
      return prepared;
    } catch (_) {
      if (_staging.existsSync()) await _staging.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<void> cancel() => AndroidSafService.cancelZip();

  // ──────────────── Helpers ────────────────

  Future<void> _requireFreeSpace(Directory on, int bytes) async {
    final free = await AndroidSafService.getFreeBytes(on.path);
    if (free == null) return; // Unknown: let the write fail loudly instead.
    final needed = bytes + _spaceMargin;
    if (free < needed) {
      throw InsufficientSpaceException(neededBytes: needed - free);
    }
  }

  Future<({int books, int dictionaries, int external})> _counts() async {
    final row = await db
        .customSelect(
          'SELECT (SELECT count(*) FROM books) AS books, '
          '(SELECT count(*) FROM dictionary_metas WHERE is_hidden = 0) '
          'AS dictionaries, '
          "(SELECT count(*) FROM books WHERE cover_image_path LIKE 'content://%') "
          'AS external',
        )
        .getSingle();
    return (
      books: row.read<int>('books'),
      dictionaries: row.read<int>('dictionaries'),
      external: row.read<int>('external'),
    );
  }

  Future<T> _withProgress<T>(
    FullBackupProgress? onProgress,
    Future<T> Function() action,
  ) async {
    final subscription = onProgress == null
        ? null
        : AndroidSafService.pollZipProgress().listen(
            (progress) => onProgress(progress.$1, progress.$2),
          );
    try {
      return await action();
    } finally {
      await subscription?.cancel();
    }
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

  String _exportFileName() {
    final now = _clock();
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
