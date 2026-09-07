import 'dart:async';
import 'dart:io';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart'
    show ocrPendingFinalizationsKey;
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
/// The import step extracts the archive into `<root>/restore_staging/`,
/// fixes up the staged database, and writes the `READY` marker last. Nothing
/// else can swap the live database while Drift holds it open, so the app
/// exits and this runs on the next cold start, before any database opens.
///
/// The swap is a handful of same-filesystem renames driven purely by what
/// exists on disk, so a process death at any point is repaired by simply
/// running again: for each item X in {database, books}, `staging/X` present
/// means the live X is still the old one. The old items wait in
/// `<root>/restore_rollback/`; that directory is never deleted while `READY`
/// exists, and `READY` goes away only once an apply or a rollback has fully
/// completed.
class StagedFullRestore {
  StagedFullRestore({required this.root, required this.prefs, this.onError});

  final Directory root;
  final SharedPreferences prefs;
  final void Function(Object error, StackTrace stackTrace)? onError;

  static const stagingDirName = 'restore_staging';
  static const rollbackDirName = 'restore_rollback';
  static const readyMarkerName = 'READY';
  static const databaseFileName = AppDatabase.databaseFileName;
  static const booksDirName = BookRepository.booksSegment;
  static const settingsEntryName = FullBackupManifest.settingsEntry;

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

  final List<FileSystemEntity> _leftovers = [];

  Directory get _staging => Directory(p.join(root.path, stagingDirName));
  Directory get _rollback => Directory(p.join(root.path, rollbackDirName));
  File get _ready => File(p.join(_staging.path, readyMarkerName));

  /// True when a launch has something to do here: a staged restore, or a
  /// rollback directory left behind by a committed one. Lets the boot path
  /// skip loading preferences on the ordinary launch.
  static bool hasWorkUnder(Directory root) =>
      File(p.join(root.path, stagingDirName, readyMarkerName)).existsSync() ||
      Directory(p.join(root.path, rollbackDirName)).existsSync();

  /// Applies a staged restore if one is ready. Returns null when nothing is
  /// staged. Never throws: failures roll back and are reported via [onError]
  /// and [resultPrefKey].
  Future<StagedRestoreOutcome?> applyIfStaged() async {
    if (!_ready.existsSync()) {
      // A READY-less staging dir belongs to an import that may be running;
      // only a rollback dir left behind by a committed run is ours to clean.
      _leftovers.add(_rollback);
      return null;
    }
    _leftovers.addAll([_staging, _rollback]);

    final firstRun = !_rollback.existsSync();
    if (firstRun && !_stagingIsComplete()) {
      // Nothing has moved yet, so there is nothing to undo.
      return _fail(const StagedRestoreException('incomplete_staging'));
    }

    try {
      _rollback.createSync(recursive: true);
      _swapIn(databaseFileName, suffixes: _databaseSuffixes);
      _swapIn(booksDirName);
      await _replacePrefs();
      await prefs.setString(resultPrefKey, resultOk);
      _ready.deleteSync();
      return StagedRestoreOutcome.applied;
    } catch (e, st) {
      _rollBack();
      return _fail(e, st);
    }
  }

  /// Deletes the staging and rollback directories once a run has committed
  /// (either way). Fire-and-forget from boot: the trees can be gigabytes.
  Future<void> deleteLeftovers() async {
    for (final entity in _leftovers) {
      try {
        if (await entity.exists()) await entity.delete(recursive: true);
      } catch (_) {
        // Best effort; the next import wipes whatever is left.
      }
    }
    _leftovers.clear();
  }

  bool _stagingIsComplete() =>
      File(p.join(_staging.path, databaseFileName)).existsSync() &&
      Directory(p.join(_staging.path, booksDirName)).existsSync() &&
      File(p.join(_staging.path, settingsEntryName)).existsSync();

  /// Moves the live item aside into the rollback dir, then the staged item
  /// into place. Skips entirely when the staged item is gone: a previous run
  /// already moved it in.
  void _swapIn(String name, {List<String> suffixes = const ['']}) {
    final staged = _existing(p.join(_staging.path, name));
    if (staged == null) return;
    for (final suffix in suffixes) {
      _existing(
        p.join(root.path, '$name$suffix'),
      )?.renameSync(p.join(_rollback.path, '$name$suffix'));
    }
    staged.renameSync(p.join(root.path, name));
  }

  /// Reverse of [_swapIn], best-effort per step so one failure cannot stop
  /// the rest: the item this run moved in goes back to staging (freeing the
  /// live slot), then the old item returns from the rollback dir.
  void _rollBack() {
    void attempt(void Function() step) {
      try {
        step();
      } catch (_) {}
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
    } catch (_) {
      // The result pref and marker are best effort on the failure path.
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
