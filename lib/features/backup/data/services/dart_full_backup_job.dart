import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_zip.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;

/// The full-backup job for iOS: the contract the Kotlin foreground service
/// answers on Android ([FullBackupJobChannel]), run in-process in Dart.
///
/// Nothing selects it yet. The wiring step overrides
/// `fullBackupJobApiProvider` (and the `jobs:` default of
/// `hasPendingFullBackupJob`) with ONE app-wide instance when
/// `Platform.isIOS`: the job's state lives in this object. Android keeps the
/// channel.
///
/// What differs from the native job, all on purpose:
/// - no journal and no resume: a job dies with the process and is simply
///   started again; [recover] clears what it left behind;
/// - plain files only: an export needs `targetPath` (a `treeUri` is refused
///   with `target_unavailable`), and a restore's `sourceUri` is a path or a
///   `file:` URI, which is what `FullBackupSource.file` hands over;
/// - nothing here keeps iOS from suspending the app mid-job; the caller
///   holds the screen awake or a background task until [finished].
class DartFullBackupJob implements FullBackupJobApi {
  DartFullBackupJob({required this.root});

  /// The app-support directory: `full_backup_job/` lives under it.
  final Directory root;

  static const _partialSuffix = '.partial';

  bool _running = false;
  bool _cancelRequested = false;

  /// A restore is writing EXTRACTED: the boot hook owns the files now.
  bool _committing = false;
  FullBackupJobKind _kind = FullBackupJobKind.export;
  String _phase = '';
  int _done = 0;
  int _total = 0;
  int _entries = 0;
  FullBackupJobStatus? _result;
  Future<void> _job = Future.value();

  /// Completes when the job in flight has ended, cleanup included. Never
  /// fails: the outcome is in [status].
  Future<void> get finished => _job;

  Directory get _jobDir =>
      Directory(p.join(root.path, StagedFullRestore.jobDirName));

  @override
  Future<void> commitJob(Map<String, Object?> spec) async {
    if (_running) throw const FullBackupJobBusyException();
    final restore = spec['kind'] == 'restore';
    _running = true;
    _cancelRequested = false;
    _committing = false;
    _kind = restore ? FullBackupJobKind.restore : FullBackupJobKind.export;
    _phase = restore ? 'extracting' : 'writing';
    _done = 0;
    _total = (spec['totalBytes'] as num?)?.toInt() ?? 0;
    _entries = 0;
    _result = null;
    _job = _run(spec, restore);
  }

  @override
  Future<FullBackupJobStatus> status() async => _running
      ? FullBackupJobStatus(
          lifecycle: FullBackupJobLifecycle.running,
          kind: _kind,
          phase: _phase,
          done: _done,
          total: _total,
          entries: _entries,
        )
      : _result ?? FullBackupJobStatus.none;

  /// Cooperative: the job stops at its next chunk or entry.
  @override
  Future<bool> cancel() async {
    if (!_running || _committing) return false;
    _cancelRequested = true;
    return true;
  }

  @override
  Future<FullBackupJobStatus?> consumeResult() async {
    final result = _result;
    _result = null;
    return result;
  }

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<ZipInspection?> inspectZip({
    required String uri,
    required String name,
  }) async {
    final peek = await peekZip(File(_filePath(uri)), name);
    return ZipInspection(
      isZip: peek.isZip,
      text: peek.text,
      complete: peek.complete,
    );
  }

  /// Launch-time cleanup of what a killed job left behind (there is nothing
  /// to resume) and of tombstones nobody finished deleting. Call once at
  /// startup, after `applyStagedFullRestoreIfAny` and before any job is
  /// prepared.
  Future<void> recover() async {
    if (_running) return;
    try {
      _clearJobFiles();
      final staging = Directory(
        p.join(root.path, StagedFullRestore.stagingDirName),
      );
      if (!_isCommitted(staging)) StagedFullRestore.retire(staging);
      for (final entity in root.listSync()) {
        if (entity.path.endsWith(StagedFullRestore.tombstoneSuffix)) {
          await entity.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // Best effort; the next launch tries again.
    }
  }

  // ──────────────── The job ────────────────

  Future<void> _run(Map<String, Object?> spec, bool restore) async {
    FullBackupJobStatus result;
    try {
      result = restore ? await _restore(spec) : await _export(spec);
    } on _Cancelled {
      result = FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.cancelled,
        kind: _kind,
      );
    } catch (e) {
      final code = _failureCode(e);
      // The error's text can carry a path, so only its type travels.
      logUsage(
        'backup.full_job_failed',
        attrs: {
          'kind': _kind.name,
          'code': code,
          'error_type': e.runtimeType.toString(),
        },
      );
      result = FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.failed,
        kind: _kind,
        error: code,
      );
    }

    // The renames free the paths before the outcome shows; the gigabytes
    // behind a tombstone go afterwards.
    Directory? tombstone;
    try {
      if (result.lifecycle != FullBackupJobLifecycle.done) {
        tombstone = _cleanup(spec, restore);
      }
      _clearJobFiles();
    } catch (_) {
      // Best effort: the next commit replaces a stale partial or staging dir.
    }
    _result = result;
    _running = false;
    await _delete(tombstone);
  }

  Future<FullBackupJobStatus> _export(Map<String, Object?> spec) async {
    final targetPath = spec['targetPath'];
    if (targetPath is! String) throw const _JobFailed('target_unavailable');
    final planFile = File(p.join(_jobDir.path, FullBackupService.planFileName));
    if (!planFile.existsSync()) throw const _JobFailed('bad_job');

    final partial = File('$targetPath$_partialSuffix');
    partial.parent.createSync(recursive: true);
    // Partials of exports that died with the process; only one job runs.
    for (final entity in partial.parent.listSync()) {
      if (entity is File && entity.path.endsWith('.zip$_partialSuffix')) {
        entity.deleteSync();
      }
    }

    var skipped = 0;
    final out = await partial.open(mode: FileMode.write);
    final writer = FullBackupZipWriter(out);
    try {
      for (final line in await planFile.readAsLines()) {
        if (line.trim().isEmpty) continue;
        _gate();
        final entry = jsonDecode(line) as Map<String, dynamic>;
        final source = File(_filePath(entry['p'] as String));
        // A source that vanished since the plan was made is never fatal.
        if (!source.existsSync()) {
          skipped++;
          continue;
        }
        await writer.add(
          entry['n'] as String,
          (entry['m'] as num?)?.toInt() ?? 0,
          (entry['l'] as num).toInt(),
          source.openRead(),
          onBytes: _onBytes,
        );
        _entries = writer.entries;
      }
      _gate();
      _phase = 'finishing';
      await writer.finish();
    } finally {
      await out.close();
    }
    partial.renameSync(targetPath);
    return FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.done,
      location: targetPath,
      bytes: writer.offset,
      entries: writer.entries,
      skippedFiles: skipped,
    );
  }

  Future<FullBackupJobStatus> _restore(Map<String, Object?> spec) async {
    const done = FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.done,
      kind: FullBackupJobKind.restore,
    );
    final staging = Directory(spec['stagingPath'] as String);
    // Already committed: the boot hook owns it, a second run is a no-op.
    if (_isCommitted(staging)) return done;
    final zip = File(_filePath(spec['sourceUri'] as String));
    if (!zip.existsSync()) throw const _JobFailed('source_missing');

    // Whatever a job that died with the process left here is not ours to
    // continue.
    await _delete(StagedFullRestore.retire(staging));
    await _delete(
      StagedFullRestore.retire(
        Directory(p.join(root.path, StagedFullRestore.rollbackDirName)),
      ),
    );
    staging.createSync(recursive: true);

    final folders = spec['folders'] as Map? ?? const {};
    final mapper = ZipNameMapper({
      for (final e in folders.entries) e.key as String: e.value as String,
    });
    final headers = readZipDirectory(zip.path);
    final handle = await zip.open();
    final made = <String>{};
    try {
      for (final header in headers) {
        _gate();
        final rel = mapper.map(header.filename);
        if (rel == null) continue;
        final target = File(ZipNameMapper.resolveInside(staging.path, rel));
        if (made.add(target.parent.path)) {
          target.parent.createSync(recursive: true);
        }
        await extractZipEntry(zip, handle, header, target, onBytes: _onBytes);
        _entries++;
      }
    } finally {
      await handle.close();
    }

    _gate();
    _phase = 'finishing';
    _committing = true;
    // ponytail: only the marker is synced, not every extracted file (that
    // is an fsync per page image); a power cut within seconds of the end
    // could stage a short file. Sync each file if that ever bites.
    File(
      p.join(staging.path, StagedFullRestore.extractedMarkerName),
    ).writeAsStringSync(spec['manifestJson'] as String? ?? '{}', flush: true);
    return done;
  }

  // ──────────────── Helpers ────────────────

  void _gate() {
    if (_cancelRequested) throw const _Cancelled();
  }

  void _onBytes(int bytes) {
    _gate();
    _done += bytes;
  }

  /// Removes what a cancelled or failed job produced. Returns the staging
  /// tombstone, if any, for the caller to delete.
  Directory? _cleanup(Map<String, Object?> spec, bool restore) {
    if (restore) {
      final staging = Directory(spec['stagingPath'] as String);
      return _isCommitted(staging) ? null : StagedFullRestore.retire(staging);
    }
    final target = spec['targetPath'];
    if (target is String) {
      final partial = File('$target$_partialSuffix');
      if (partial.existsSync()) partial.deleteSync();
    }
    return null;
  }

  /// Removes every file of the job directory: the snapshot alone can be
  /// gigabytes.
  void _clearJobFiles() {
    if (!_jobDir.existsSync()) return;
    for (final entity in _jobDir.listSync()) {
      entity.deleteSync(recursive: true);
    }
  }

  static Future<void> _delete(Directory? tombstone) async {
    try {
      await tombstone?.delete(recursive: true);
    } on FileSystemException {
      // [recover] sweeps it on a later launch.
    }
  }

  static bool _isCommitted(Directory staging) => [
    StagedFullRestore.extractedMarkerName,
    StagedFullRestore.readyMarkerName,
  ].any((marker) => File(p.join(staging.path, marker)).existsSync());

  /// A plain path, or a `file:` URI as a path.
  static String _filePath(String pathOrUri) => pathOrUri.startsWith('file:')
      ? Uri.parse(pathOrUri).toFilePath()
      : pathOrUri;

  /// The codes the Kotlin runner reports, plus `io_error` for what it would
  /// have paused on and retried.
  static String _failureCode(Object e) => switch (e) {
    _JobFailed(:final code) => code,
    CorruptZipException() => 'corrupt_archive',
    UnsafeZipEntryException() => 'unsafe_archive',
    ArgumentError() ||
    StateError() ||
    TypeError() ||
    FormatException() => 'bad_job',
    _ => 'io_error',
  };
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _JobFailed implements Exception {
  final String code;
  const _JobFailed(this.code);
}
