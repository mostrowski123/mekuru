import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
      Sentry.logger.info('Manual backup created', attributes: {
        'category': SentryAttribute.string('backup'),
      });
      Sentry.metrics.count('backup.created', 1, attributes: {
        'type': SentryAttribute.string('manual'),
      });
      _showSuccess(const BackupMessage.backupCreated());
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
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
      // Try FileType.custom first — on stock Android this greys out
      // non-.mekuru files. If it fails (some OEMs don't support custom
      // extension filtering), fall back to FileType.any.
      PlatformFile? picked;
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mekuru'],
        );
        if (result == null || result.files.isEmpty) return;
        picked = result.files.single;
      } catch (_) {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result == null || result.files.isEmpty) return;
        picked = result.files.single;
      }

      final filePath = picked.path;
      if (filePath == null) return;

      if (!filePath.endsWith('.mekuru')) {
        state = const RestoreState(error: BackupMessage.invalidBackupFile());
        return;
      }

      await _restoreFromPath(filePath, queueDictionaryPreferences: true);
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

      // Restore books
      final booksResult = await restoreService.restoreBooks(manifest);

      final result = RestoreResult(
        settingsRestored: settingsOk,
        dictionaryPreferencesResult: dictionaryPreferencesResult,
        wordsResult: wordsResult,
        booksResult: booksResult,
        errors: errors,
      );

      Sentry.logger.info('Backup restored', attributes: {
        'category': SentryAttribute.string('backup'),
      });
      Sentry.metrics.count('backup.restored', 1);

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
      Sentry.logger.info('Auto-backup completed', attributes: {
        'category': SentryAttribute.string('backup'),
      });
      Sentry.metrics.count('backup.created', 1, attributes: {
        'type': SentryAttribute.string('auto'),
      });
    } catch (e, st) {
      Sentry.logger.error('Auto-backup failed: $e', attributes: {
        'category': SentryAttribute.string('backup'),
      });
      Sentry.captureException(e, stackTrace: st);
    }
  }
});
