import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/main.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────── Service Providers ────────────────

final bookMatchServiceProvider = Provider<BookMatchService>((ref) {
  return BookMatchService();
});

final pendingBookDataRepositoryProvider = Provider<PendingBookDataRepository>((
  ref,
) {
  return PendingBookDataRepository(ref.watch(databaseProvider));
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(databaseProvider),
    ref.watch(bookMatchServiceProvider),
  );
});

final restoreServiceProvider = Provider<RestoreService>((ref) {
  return RestoreService(
    ref.watch(databaseProvider),
    ref.watch(bookMatchServiceProvider),
    ref.watch(pendingBookDataRepositoryProvider),
  );
});

final backupFileManagerProvider = Provider<BackupFileManager>((ref) {
  return BackupFileManager();
});

final backupSchedulerProvider = Provider<BackupScheduler>((ref) {
  return BackupScheduler();
});

final pendingDictionaryRestoreServiceProvider =
    Provider<PendingDictionaryRestoreService>((ref) {
      return PendingDictionaryRestoreService();
    });

final pendingDictionaryRestorePreviewProvider =
    FutureProvider<PendingDictionaryRestorePreview?>((ref) async {
      ref.watch(dictionariesProvider);
      final service = ref.watch(pendingDictionaryRestoreServiceProvider);
      final repository = ref.watch(dictionaryRepositoryProvider);
      return service.getPendingRestorePreview(repository);
    });

// ──────────────── Backup State ────────────────

enum BackupMessageKind {
  backupCreated,
  backupFailed,
  noBackupsToExport,
  backupExported,
  exportFailed,
  invalidBackupFile,
  couldNotOpenFile,
  restoreSummary,
  restoreFailed,
  booksUpdatedFromBackup,
  applyBookDataFailed,
  // A .zip picked where a .mekuru was expected, and vice versa.
  wrongKindFullBackup,
  wrongKindReadingData,
  // Full backup (details carries a preformatted size or a version). Progress
  // and outcomes live on the job page; these are the refusals before a job
  // is committed.
  fullBusy,
  fullNotEnoughSpace,
  fullTooNew,
  fullInvalid,
  fullIncomplete,
  fullPendingRestore,
  fullFailed,
  fullRestoreFailed,
}

class BackupMessage {
  const BackupMessage._({
    required this.kind,
    this.details,
    this.count,
    this.result,
  });

  final BackupMessageKind kind;
  final String? details;
  final int? count;
  final RestoreResult? result;

  const BackupMessage.backupCreated()
    : this._(kind: BackupMessageKind.backupCreated);

  const BackupMessage.backupFailed(String details)
    : this._(kind: BackupMessageKind.backupFailed, details: details);

  const BackupMessage.noBackupsToExport()
    : this._(kind: BackupMessageKind.noBackupsToExport);

  const BackupMessage.backupExported()
    : this._(kind: BackupMessageKind.backupExported);

  const BackupMessage.exportFailed(String details)
    : this._(kind: BackupMessageKind.exportFailed, details: details);

  const BackupMessage.invalidBackupFile()
    : this._(kind: BackupMessageKind.invalidBackupFile);

  const BackupMessage.couldNotOpenFile(String details)
    : this._(kind: BackupMessageKind.couldNotOpenFile, details: details);

  const BackupMessage.restoreSummary(RestoreResult result)
    : this._(kind: BackupMessageKind.restoreSummary, result: result);

  const BackupMessage.restoreFailed(String details)
    : this._(kind: BackupMessageKind.restoreFailed, details: details);

  const BackupMessage.booksUpdatedFromBackup(int count)
    : this._(kind: BackupMessageKind.booksUpdatedFromBackup, count: count);

  const BackupMessage.applyBookDataFailed(String details)
    : this._(kind: BackupMessageKind.applyBookDataFailed, details: details);

  const BackupMessage.wrongKindFullBackup()
    : this._(kind: BackupMessageKind.wrongKindFullBackup);

  const BackupMessage.wrongKindReadingData()
    : this._(kind: BackupMessageKind.wrongKindReadingData);

  const BackupMessage.fullBusy() : this._(kind: BackupMessageKind.fullBusy);

  const BackupMessage.fullNotEnoughSpace(String size)
    : this._(kind: BackupMessageKind.fullNotEnoughSpace, details: size);

  const BackupMessage.fullTooNew(String version)
    : this._(kind: BackupMessageKind.fullTooNew, details: version);

  const BackupMessage.fullInvalid()
    : this._(kind: BackupMessageKind.fullInvalid);

  const BackupMessage.fullIncomplete()
    : this._(kind: BackupMessageKind.fullIncomplete);

  const BackupMessage.fullPendingRestore()
    : this._(kind: BackupMessageKind.fullPendingRestore);

  const BackupMessage.fullFailed(String details)
    : this._(kind: BackupMessageKind.fullFailed, details: details);

  const BackupMessage.fullRestoreFailed(String details)
    : this._(kind: BackupMessageKind.fullRestoreFailed, details: details);
}

class BackupState {
  final bool isWorking;
  final BackupMessage? error;
  final BackupMessage? successMessage;

  const BackupState({this.isWorking = false, this.error, this.successMessage});
}

class BackupNotifier extends Notifier<BackupState> {
  Timer? _autoDismissTimer;

  @override
  BackupState build() => const BackupState();

  /// Create a manual backup.
  Future<void> createBackup() async {
    state = const BackupState(isWorking: true);
    try {
      final service = ref.read(backupServiceProvider);
      final fileManager = ref.read(backupFileManagerProvider);
      final manifest = await service.createBackup();
      await fileManager.createBackupFile(manifest);
      ref.invalidate(backupHistoryProvider);
      logUsage('backup.created', attrs: {'type': 'manual'});
      _showSuccess(const BackupMessage.backupCreated());
    } catch (e, st) {
      logFailure('backup.failed', e, stackTrace: st, attrs: {'type': 'manual'});
      state = BackupState(error: BackupMessage.backupFailed(e.toString()));
    }
  }

  /// Export the most recent backup file via the system file browser.
  Future<void> exportLatestBackup({required String dialogTitle}) async {
    state = const BackupState(isWorking: true);
    try {
      final fileManager = ref.read(backupFileManagerProvider);
      final backups = await fileManager.listBackups();
      if (backups.isEmpty) {
        state = const BackupState(error: BackupMessage.noBackupsToExport());
        return;
      }
      final saved = await fileManager.exportBackupFile(
        backups.first.filePath,
        dialogTitle: dialogTitle,
      );
      if (saved) {
        _showSuccess(const BackupMessage.backupExported());
      } else {
        state = const BackupState();
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = BackupState(error: BackupMessage.exportFailed(e.toString()));
    }
  }

  void clearState() {
    _autoDismissTimer?.cancel();
    state = const BackupState();
  }

  void _showSuccess(BackupMessage message) {
    _autoDismissTimer?.cancel();
    state = BackupState(successMessage: message);
    _autoDismissTimer = Timer(const Duration(seconds: 3), clearState);
  }
}

final backupNotifierProvider = NotifierProvider<BackupNotifier, BackupState>(
  BackupNotifier.new,
);

// ──────────────── Restore State ────────────────

class RestoreState {
  final bool isWorking;
  final BackupMessage? error;
  final BackupMessage? successMessage;
  final RestoreResult? result;
  final List<BookRestoreConflict>? pendingConflicts;

  const RestoreState({
    this.isWorking = false,
    this.error,
    this.successMessage,
    this.result,
    this.pendingConflicts,
  });
}

class RestoreNotifier extends Notifier<RestoreState> {
  Timer? _autoDismissTimer;

  @override
  RestoreState build() => const RestoreState();

  /// Restore from an external file (via file picker).
  Future<void> restoreFromFilePicker() async {
    try {
      final picked = await BackupFileManager.pickReadingDataBackup();
      final filePath = picked?.path;
      if (filePath == null) return;
      await _restoreFromPath(filePath, queueDictionaryPreferences: true);
    } on WrongBackupKindException {
      state = const RestoreState(error: BackupMessage.wrongKindFullBackup());
    } on BackupFormatException {
      state = const RestoreState(error: BackupMessage.invalidBackupFile());
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = RestoreState(error: BackupMessage.couldNotOpenFile(e.toString()));
    }
  }

  /// Restore from a backup file path (internal backups list).
  Future<void> restoreFromPath(
    String filePath, {
    bool queueDictionaryPreferences = true,
  }) async {
    await _restoreFromPath(
      filePath,
      queueDictionaryPreferences: queueDictionaryPreferences,
    );
  }

  Future<void> _restoreFromPath(
    String filePath, {
    required bool queueDictionaryPreferences,
  }) async {
    state = const RestoreState(isWorking: true);
    try {
      final fileManager = ref.read(backupFileManagerProvider);
      final restoreService = ref.read(restoreServiceProvider);
      final pendingDictionaryRestoreService = ref.read(
        pendingDictionaryRestoreServiceProvider,
      );
      final dictionaryRepository = ref.read(dictionaryRepositoryProvider);

      final manifest = await fileManager.importBackupFile(filePath);
      final errors = <String>[];

      // Restore settings
      final settingsOk = await restoreService.restoreSettings(manifest);
      if (!settingsOk) errors.add('Some settings could not be restored');

      // Reload all in-memory settings providers from SharedPreferences
      if (settingsOk) await _reloadSettingsProviders();

      final dictionaryPreferencesResult = await pendingDictionaryRestoreService
          .queueFromBackup(
            preferences: manifest.dictionaryPreferences,
            shouldQueue: queueDictionaryPreferences,
            repository: dictionaryRepository,
          );
      ref.invalidate(pendingDictionaryRestorePreviewProvider);

      // Restore saved words
      final wordsResult = await restoreService.restoreSavedWords(manifest);

      // Restore reading stats (only into empty stats tables)
      await restoreService.restoreStats(manifest);

      // Restore books
      final booksResult = await restoreService.restoreBooks(manifest);

      final result = RestoreResult(
        settingsRestored: settingsOk,
        dictionaryPreferencesResult: dictionaryPreferencesResult,
        wordsResult: wordsResult,
        booksResult: booksResult,
        errors: errors,
      );

      logUsage('backup.restored');

      // If backup contains highlights, user was likely Pro — try restoring purchases
      final hasHighlights = manifest.books.any((b) => b.highlights.isNotEmpty);
      if (hasHighlights) {
        _tryRestorePurchases();
      }

      if (booksResult.conflicts.isNotEmpty) {
        state = RestoreState(
          result: result,
          pendingConflicts: booksResult.conflicts,
        );
      } else {
        _showSuccess(BackupMessage.restoreSummary(result));
      }
    } on WrongBackupKindException {
      state = const RestoreState(error: BackupMessage.wrongKindFullBackup());
    } on BackupVersionException catch (e) {
      state = RestoreState(error: BackupMessage.restoreFailed(e.toString()));
    } on BackupFormatException catch (e) {
      state = RestoreState(error: BackupMessage.restoreFailed(e.toString()));
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = RestoreState(error: BackupMessage.restoreFailed(e.toString()));
    }
  }

  /// Apply selected conflicts (user chose to overwrite).
  Future<void> applyConflicts(List<BookRestoreConflict> toApply) async {
    state = const RestoreState(isWorking: true);
    try {
      final restoreService = ref.read(restoreServiceProvider);
      for (final conflict in toApply) {
        await restoreService.applyBookData(
          conflict.existingBook.id,
          conflict.backupEntry,
        );
      }
      _showSuccess(BackupMessage.booksUpdatedFromBackup(toApply.length));
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = RestoreState(
        error: BackupMessage.applyBookDataFailed(e.toString()),
      );
    }
  }

  void clearState() {
    _autoDismissTimer?.cancel();
    state = const RestoreState();
  }

  void _showSuccess(BackupMessage message) {
    _autoDismissTimer?.cancel();
    state = RestoreState(successMessage: message);
    _autoDismissTimer = Timer(const Duration(seconds: 5), clearState);
  }

  /// Force-refresh settings providers so restored values are applied
  /// immediately in memory and reflected by the UI.
  Future<void> _reloadSettingsProviders() async {
    await ref.refresh(appLanguageProvider.notifier).loadPersistedSettings();
    await ref.refresh(appThemeModeProvider.notifier).loadPersistedSettings();
    await ref.refresh(appColorThemeProvider.notifier).loadPersistedSettings();
    await ref.refresh(lookupFontSizeProvider.notifier).loadPersistedSettings();
    await ref.refresh(searchHistoryProvider.notifier).loadPersistedSettings();
    await ref
        .refresh(filterRomanLettersProvider.notifier)
        .loadPersistedSettings();
    await ref.refresh(ankidroidConfigProvider.notifier).loadPersistedSettings();
    await ref.refresh(startupScreenProvider.notifier).loadPersistedSettings();
    await ref.refresh(autoFocusSearchProvider.notifier).loadPersistedSettings();
    await ref
        .refresh(autoCropWhiteThresholdProvider.notifier)
        .loadPersistedSettings();
    await ref.refresh(ocrServerUrlProvider.notifier).loadPersistedSettings();
    await ref.refresh(readerSettingsProvider.notifier).loadPersistedSettings();
    await ref.refresh(librarySortProvider.notifier).loadPersistedSort();

    // FutureProvider state is derived directly from SharedPreferences.
    ref.invalidate(autoBackupIntervalProvider);
  }

  /// Best-effort purchase restoration - fire and forget.

  void _tryRestorePurchases() {
    unawaited(
      Future(() async {
        try {
          await OcrStoreService.instance.restorePurchases();
          ref.invalidate(proUnlockedProvider);
          debugPrint('[Backup] Purchase restoration triggered');
        } catch (e) {
          debugPrint('[Backup] Purchase restoration failed (non-fatal): $e');
        }
      }),
    );
  }
}

final restoreNotifierProvider = NotifierProvider<RestoreNotifier, RestoreState>(
  RestoreNotifier.new,
);

// ──────────────── Full Backup ────────────────

/// The real full-backup service, bound to this device's directories.
final fullBackupServiceProvider = FutureProvider<FullBackupApi>((ref) async {
  final (info, root) = await (
    PackageInfo.fromPlatform(),
    getApplicationSupportDirectory(),
  ).wait;
  return FullBackupService(
    db: ref.watch(databaseProvider),
    backupService: ref.watch(backupServiceProvider),
    root: root,
    appVersion: info.version,
    jobs: ref.watch(fullBackupJobApiProvider),
  );
});

/// The two system pickers the full backup screen opens, already mapped to
/// archive endpoints. Injected so widget tests can script them and
/// integration tests can point the real service at plain files instead of
/// SAF dialogs.
class FullBackupPickers {
  final Future<FullBackupTarget?> Function() pickExportTarget;
  final Future<FullBackupSource?> Function() pickSource;

  const FullBackupPickers({
    required this.pickExportTarget,
    required this.pickSource,
  });
}

final fullBackupPickersProvider = Provider<FullBackupPickers>((ref) {
  return FullBackupPickers(
    pickExportTarget: () async {
      final folder = await AndroidSafService.pickDirectory();
      return folder == null ? null : FullBackupTarget.tree(folder.treeUri);
    },
    pickSource: () async {
      final document = await AndroidSafService.pickDocument();
      return document == null
          ? null
          : FullBackupSource.uri(document.uri, sizeBytes: document.sizeBytes);
    },
  );
});

class FullBackupState {
  /// A refusal or failure before a job was committed; the job page owns
  /// everything after that.
  final BackupMessage? error;

  /// True from the tap until the job is committed or refused.
  final bool busy;

  const FullBackupState({this.error, this.busy = false});
}

/// Starts full backups and restores: pickers, validation, the Dart-side
/// preparation, then hands the job to the native service. Progress and
/// outcomes are followed by [fullBackupJobProvider].
class FullBackupNotifier extends Notifier<FullBackupState> {
  @override
  FullBackupState build() => const FullBackupState();

  /// Folder picker → snapshot, plan, commit.
  Future<void> exportToFolder() async {
    if (state.busy) return;
    final target = await ref.read(fullBackupPickersProvider).pickExportTarget();
    if (target == null) return;
    await _commitJob(
      FullBackupJobKind.export,
      (api) => api.prepareExport(target),
    );
  }

  /// Document picker → manifest validation. Returns what the confirmation
  /// dialogs show, or null when the picker was dismissed or the file refused.
  Future<FullBackupPreview?> pickAndInspect() async {
    if (state.busy) return null;
    final source = await ref.read(fullBackupPickersProvider).pickSource();
    if (source == null) return null;

    state = const FullBackupState(busy: true);
    try {
      final api = await ref.read(fullBackupServiceProvider.future);
      final preview = await api.inspect(source);
      state = const FullBackupState();
      return preview;
    } catch (e, st) {
      state = FullBackupState(error: _messageFor(e, st, restoring: true));
      return null;
    }
  }

  /// Commits the restore job; the job page takes over from here.
  Future<void> startRestore(FullBackupPreview preview) async {
    if (state.busy) return;
    await _commitJob(
      FullBackupJobKind.restore,
      (api) => api.startRestore(preview),
    );
  }

  /// Blocks the app, asks for the notification permission (the answer does
  /// not gate the job; a denial only hides the progress notification), runs
  /// the Dart-side preparation and hands the job to the service. A refusal
  /// before commit releases the app and becomes a snackbar.
  Future<void> _commitJob(
    FullBackupJobKind kind,
    Future<void> Function(FullBackupApi api) prepare,
  ) async {
    final job = ref.read(fullBackupJobProvider.notifier);
    state = const FullBackupState(busy: true);
    job.markPreparing(kind);
    try {
      await ref.read(fullBackupJobApiProvider).requestNotificationPermission();
      await prepare(await ref.read(fullBackupServiceProvider.future));
      await job.jobCommitted(kind);
      state = const FullBackupState();
    } catch (e, st) {
      job.preparationFailed();
      state = FullBackupState(
        error: _messageFor(e, st, restoring: kind == FullBackupJobKind.restore),
      );
    }
  }

  void clearState() => state = const FullBackupState();

  static BackupMessage _messageFor(
    Object error,
    StackTrace stackTrace, {
    required bool restoring,
  }) {
    final message = switch (error) {
      FullBackupBusyException() => const BackupMessage.fullBusy(),
      InsufficientSpaceException(:final neededBytes) =>
        BackupMessage.fullNotEnoughSpace(formatBytes(neededBytes)),
      FullBackupTooNewException(:final appVersion) => BackupMessage.fullTooNew(
        appVersion,
      ),
      WrongBackupKindException(found: BackupKind.readingData) =>
        const BackupMessage.wrongKindReadingData(),
      WrongBackupKindException() => const BackupMessage.wrongKindFullBackup(),
      FullBackupIncompleteException() => const BackupMessage.fullIncomplete(),
      FullBackupFormatException() ||
      BackupFormatException() => const BackupMessage.fullInvalid(),
      FullBackupPendingRestoreException() =>
        const BackupMessage.fullPendingRestore(),
      _ =>
        restoring
            ? BackupMessage.fullRestoreFailed(error.toString())
            : BackupMessage.fullFailed(error.toString()),
    };
    if (message.kind == BackupMessageKind.fullFailed ||
        message.kind == BackupMessageKind.fullRestoreFailed) {
      logFailure(
        restoring ? 'backup.full_restore_failed' : 'backup.full_export_failed',
        error,
        stackTrace: stackTrace,
      );
    }
    return message;
  }
}

final fullBackupNotifierProvider =
    NotifierProvider<FullBackupNotifier, FullBackupState>(
      FullBackupNotifier.new,
    );

/// Returns and clears the outcome the boot-time apply left behind:
/// [StagedFullRestore.resultOk] or `error:<code>`. Consumed once so the
/// message shows on one launch only.
Future<String?> consumeFullRestoreResult() async {
  final prefs = await SharedPreferences.getInstance();
  final result = prefs.getString(StagedFullRestore.resultPrefKey);
  if (result != null) await prefs.remove(StagedFullRestore.resultPrefKey);
  return result;
}

// ──────────────── Backup History ────────────────

final backupHistoryProvider = FutureProvider<List<BackupFileInfo>>((ref) {
  return ref.watch(backupFileManagerProvider).listBackups();
});

// ──────────────── Auto-Backup ────────────────

final autoBackupIntervalProvider = FutureProvider<BackupInterval>((ref) async {
  return ref.watch(backupSchedulerProvider).getInterval();
});

/// Runs once at startup: checks if auto-backup is due and performs it.
final autoBackupCheckerProvider = FutureProvider<void>((ref) async {
  final scheduler = ref.read(backupSchedulerProvider);
  if (await scheduler.isBackupDue()) {
    try {
      final service = ref.read(backupServiceProvider);
      final fileManager = ref.read(backupFileManagerProvider);
      final manifest = await service.createBackup();
      await fileManager.createBackupFile(manifest, isAuto: true);
      await scheduler.recordAutoBackup();
      logUsage('backup.created', attrs: {'type': 'auto'});
    } catch (e, st) {
      logFailure('backup.failed', e, stackTrace: st, attrs: {'type': 'auto'});
    }
  }
});
