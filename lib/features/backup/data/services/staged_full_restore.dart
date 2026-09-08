import 'dart:async';
import 'dart:io';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/prepare_staged_restore.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart'
    show ocrPendingFinalizationsKey;
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StagedRestoreOutcome { applied, rolledBack }

/// Thrown when the staging directory is not what the import step promised.
class StagedRestoreException implements Exception {
  final String code;
  const StagedRestoreException(this.code);

  @override
  String toString() => 'Staged restore failed: $code';
}

/// Boot-time half of a full restore.
///
/// The native job unpacks the archive into `<root>/restore_staging/` in the
/// on-device layout and writes the `EXTRACTED` marker last. Nothing else can
/// swap the live database while Drift holds it open, so the app exits and
/// this runs on the next cold start, before any database opens: first the
/// fix-ups ([prepareStagedRestore], which ends by writing `READY`), then the
/// swap.
///
/// The swap is a handful of same-filesystem renames driven purely by what
/// exists on disk, so a process death at any point is repaired by simply
/// running again: for each item X in {database, books, unidic-lite},
/// `staging/X` present means the live X is still the old one. The old items
/// wait in `<root>/restore_rollback/`; that directory is never deleted while
/// `READY` exists, and `READY` goes away only once an apply or a rollback has
/// fully completed. Directories are never deleted in place: they are renamed
/// to a `*.trash` tombstone first, so the path is free at once and a
/// concurrent job can never write into a tree that is being removed.
///
/// The database and `books/` live under [root] (app support); the downloaded
/// UniDic-lite lives under [documentsRoot] (app documents) and is optional:
/// an archive without it leaves the device's own copy alone.
class StagedFullRestore {
  StagedFullRestore({
    required this.root,
    required this.documentsRoot,
    required this.prefs,
    this.onError,
    Future<void> Function(int connectionId)? clearServerSecret,
  }) : _clearServerSecret = clearServerSecret ?? ServerSecretStorage().clear;

  final Directory root;
  final Directory documentsRoot;
  final SharedPreferences prefs;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final Future<void> Function(int connectionId) _clearServerSecret;

  static const stagingDirName = 'restore_staging';
  static const rollbackDirName = 'restore_rollback';
  static const readyMarkerName = 'READY';
  static const extractedMarkerName = 'EXTRACTED';
  static const jobDirName = 'full_backup_job';
  static const cancelledMarkerName = 'CANCELLED';
  static const tombstoneSuffix = '.trash';
  static const databaseFileName = AppDatabase.databaseFileName;
  static const booksDirName = BookRepository.booksSegment;
  static const settingsEntryName = FullBackupManifest.settingsFileName;
  static const unidicDirName = FullBackupManifest.unidicDirName;

  /// `ok`, or `error:<code>`; consumed once by the UI after the restart.
  static const resultPrefKey = 'backup.full_restore_result';
  static const resultOk = 'ok';
  static const resultErrorPrefix = 'error:';

  /// Journal first so a hot journal is never left beside a database it does
  /// not belong to (SQLite would replay it into the new file); bare file last.
  static const _databaseSuffixes = ['-journal', '-wal', '-shm', ''];

  /// The only preferences that survive the wipe: device history, never app
  /// state keyed by book ids that mean something else in the restored library.
  static const _keepPrefKeys = {ocrPendingFinalizationsKey};
  static const _keepPrefPrefixes = [
    SharedPreferencesReviewPromptStorage.keyPrefix,
  ];

  final List<Directory> _leftovers = [];

  Directory get _staging => Directory(p.join(root.path, stagingDirName));
  Directory get _rollback => Directory(p.join(root.path, rollbackDirName));
  File get _ready => File(p.join(_staging.path, readyMarkerName));
  File get _extracted => File(p.join(_staging.path, extractedMarkerName));
  File get _jobCancelled =>
      File(p.join(root.path, jobDirName, cancelledMarkerName));

  /// True when a launch has something to do here: a staged restore, or a
  /// rollback directory left behind by a committed one. Lets the boot path
  /// skip loading preferences on the ordinary launch.
  static bool hasWorkUnder(Directory root) =>
      hasStagedRestore(root) ||
      Directory(p.join(root.path, rollbackDirName)).existsSync();

  /// True while a restore is waiting to be applied on the next cold start.
  static bool hasStagedRestore(Directory root) =>
      File(p.join(root.path, stagingDirName, readyMarkerName)).existsSync() ||
      File(p.join(root.path, stagingDirName, extractedMarkerName)).existsSync();

  /// Renames [dir] to a unique sibling tombstone and returns it, or null when
  /// there was nothing to retire. The gigabytes behind it are deleted later.
  static Directory? retire(Directory dir) {
    if (!dir.existsSync()) return null;
    final tombstone = Directory(
      '${dir.path}.${DateTime.now().microsecondsSinceEpoch}$tombstoneSuffix',
    );
    try {
      return dir.renameSync(tombstone.path);
    } on FileSystemException {
      // Rename refused: fall back to deleting in place.
      dir.deleteSync(recursive: true);
      return null;
    }
  }

  /// Applies a staged restore if one is ready. Returns null when nothing is
  /// staged. Never throws: failures roll back and are reported via [onError]
  /// and [resultPrefKey].
  Future<StagedRestoreOutcome?> applyIfStaged() async {
    if (!_ready.existsSync()) {
      // A staging dir carrying neither marker belongs to a job that may be
      // running (or that cancel is still cleaning up); only a rollback dir
      // left behind by a committed run is ours to clean.
      if (!_extracted.existsSync() || _jobCancelled.existsSync()) {
        _leftovers.add(_rollback);
        return null;
      }
      try {
        await _prepare();
      } catch (e, st) {
        _leftovers.addAll([_staging, _rollback]);
        return _fail(e, st);
      }
    }
    _leftovers.addAll([_staging, _rollback]);

    final firstRun = !_rollback.existsSync();
    if (firstRun && !_stagingIsComplete()) {
      // Nothing has moved yet, so there is nothing to undo.
      return _fail(const StagedRestoreException('incomplete_staging'));
    }

    var movedUnidic = false;
    try {
      _rollback.createSync(recursive: true);
      _swapIn(databaseFileName, suffixes: _databaseSuffixes);
      _swapIn(booksDirName);
      movedUnidic = _swapIn(unidicDirName, into: documentsRoot);
      await _replacePrefs();
      await prefs.setString(resultPrefKey, resultOk);
      _ready.deleteSync();
      return StagedRestoreOutcome.applied;
    } catch (e, st) {
      _rollBack(movedUnidic: movedUnidic);
      return _fail(e, st);
    }
  }

  /// Retires then deletes the staging and rollback directories once a run
  /// has committed (either way). Fire-and-forget from boot: the trees can be
  /// gigabytes, but the renames free the paths immediately.
  Future<void> deleteLeftovers() async {
    final tombstones = <Directory>[];
    for (final dir in _leftovers) {
      try {
        final tombstone = retire(dir);
        if (tombstone != null) tombstones.add(tombstone);
      } catch (_) {
        // Best effort; the next launch sweeps whatever is left.
      }
    }
    _leftovers.clear();
    for (final tombstone in tombstones) {
      try {
        await tombstone.delete(recursive: true);
      } catch (_) {
        // The native recovery sweeps tombstones too.
      }
    }
  }

  /// The fix-ups the job left to boot: validate and rewrite the staged
  /// database, forget secrets whose ids the archive reuses, write READY.
  Future<void> _prepare() async {
    final prepared = await prepareStagedRestore(
      PrepareStagedRestoreArgs(
        stagingPath: _staging.path,
        rootPath: root.path,
        manifestJson: _extracted.readAsStringSync(),
      ),
    );
    // Secrets are keyed by connection id; the restored ids can collide with
    // this device's old connections, so never let a stale secret pair with a
    // restored URL.
    for (final id in prepared.serverConnectionIds) {
      await _clearServerSecret(id);
    }
    _extracted.deleteSync();
  }

  bool _stagingIsComplete() =>
      File(p.join(_staging.path, databaseFileName)).existsSync() &&
      Directory(p.join(_staging.path, booksDirName)).existsSync() &&
      File(p.join(_staging.path, settingsEntryName)).existsSync();

  /// Moves the live item (under [into], default [root]) aside into the
  /// rollback dir, then the staged item into place. Returns false without
  /// touching anything when the staged item is gone: a previous run already
  /// moved it in, or the archive never had it.
  bool _swapIn(
    String name, {
    List<String> suffixes = const [''],
    Directory? into,
  }) {
    final staged = _existing(p.join(_staging.path, name));
    if (staged == null) return false;
    final live = into ?? root;
    live.createSync(recursive: true);
    for (final suffix in suffixes) {
      _existing(
        p.join(live.path, '$name$suffix'),
      )?.renameSync(p.join(_rollback.path, '$name$suffix'));
    }
    staged.renameSync(p.join(live.path, name));
    return true;
  }

  /// Reverse of [_swapIn], best-effort per step so one failure cannot stop
  /// the rest: the item this run moved in goes back to staging (freeing the
  /// live slot), then the old item returns from the rollback dir.
  ///
  /// The database and books are always staged, so "live present, staged
  /// gone" identifies the item as ours even across a crash. The optional
  /// dictionary is ours when this run moved it ([movedUnidic]) or when an
  /// old one waits in the rollback dir; a crash between runs on a device
  /// that had none leaves the restored dictionary in place, which is a
  /// working dictionary either way.
  void _rollBack({required bool movedUnidic}) {
    void attempt(void Function() step) {
      try {
        step();
      } catch (_) {}
    }

    final stagedUnidic = p.join(_staging.path, unidicDirName);
    final oldUnidic = _existing(p.join(_rollback.path, unidicDirName));
    if (movedUnidic || oldUnidic != null) {
      final live = _existing(p.join(documentsRoot.path, unidicDirName));
      if (live != null && _existing(stagedUnidic) == null) {
        attempt(() => live.renameSync(stagedUnidic));
      }
    }
    if (oldUnidic != null) {
      attempt(
        () => oldUnidic.renameSync(p.join(documentsRoot.path, unidicDirName)),
      );
    }

    for (final (name, suffixes) in [
      (booksDirName, const ['']),
      (databaseFileName, _databaseSuffixes),
    ]) {
      final stagedPath = p.join(_staging.path, name);
      final live = _existing(p.join(root.path, name));
      if (live != null && _existing(stagedPath) == null) {
        attempt(() => live.renameSync(stagedPath));
      }
      for (final suffix in suffixes.reversed) {
        final old = _existing(p.join(_rollback.path, '$name$suffix'));
        if (old != null) {
          attempt(() => old.renameSync(p.join(root.path, '$name$suffix')));
        }
      }
    }
  }

  Future<void> _replacePrefs() async {
    // Decode before clearing: a corrupt settings file must fail while the
    // old preferences are still intact.
    final settings = BackupSerializer.decode(
      await File(p.join(_staging.path, settingsEntryName)).readAsString(),
    ).settings;

    final keep = <String, dynamic>{
      for (final key in prefs.getKeys())
        if (_keepPrefKeys.contains(key) ||
            _keepPrefPrefixes.any(key.startsWith))
          key: prefs.get(key),
    };
    await prefs.clear();
    await RestoreService.applySettings(prefs, settings);
    await RestoreService.applySettings(
      prefs,
      BackupSettings(app: keep, reader: const {}),
    );
  }

  Future<StagedRestoreOutcome> _fail(
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    final code = error is StagedRestoreException
        ? error.code
        : error.runtimeType.toString();
    try {
      await prefs.setString(resultPrefKey, '$resultErrorPrefix$code');
      if (_ready.existsSync()) _ready.deleteSync();
      if (_extracted.existsSync()) _extracted.deleteSync();
    } catch (_) {
      // The result pref and markers are best effort on the failure path.
    }
    onError?.call(error, stackTrace ?? StackTrace.current);
    return StagedRestoreOutcome.rolledBack;
  }

  static FileSystemEntity? _existing(String path) =>
      switch (FileSystemEntity.typeSync(path)) {
        FileSystemEntityType.notFound => null,
        FileSystemEntityType.directory => Directory(path),
        _ => File(path),
      };
}

/// Boot hook: applies a staged full restore before any database is opened.
/// Runs first inside `main`'s app runner and never throws.
Future<void> applyStagedFullRestoreIfAny() async {
  try {
    final root = await getApplicationSupportDirectory();
    if (!StagedFullRestore.hasWorkUnder(root)) return;
    final restore = StagedFullRestore(
      root: root,
      documentsRoot: await getApplicationDocumentsDirectory(),
      prefs: await SharedPreferences.getInstance(),
      onError: (error, stackTrace) => logFailure(
        'backup.full_restore_boot_failed',
        error,
        stackTrace: stackTrace,
      ),
    );
    final outcome = await restore.applyIfStaged();
    if (outcome != null) {
      logUsage('backup.full_restore_boot', attrs: {'outcome': outcome.name});
    }
    unawaited(restore.deleteLeftovers());
  } catch (e, st) {
    logFailure('backup.full_restore_boot_failed', e, stackTrace: st);
  }
}
