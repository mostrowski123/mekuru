import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/database/database_provider.dart';
import 'core/platform/ios_storage.dart';
import 'core/services/analytics_service.dart';
import 'core/services/firebase_runtime.dart';
import 'core/services/sentry_helpers.dart';
import 'core/services/sentry_setup.dart';
import 'core/services/usage_telemetry.dart';
import 'features/backup/data/services/staged_full_restore.dart';
import 'features/backup/data/services/full_backup_service.dart'
    show hasPendingFullBackupJob;
import 'features/backup/data/services/ios_full_backup.dart';
import 'features/backup/presentation/providers/full_backup_job_provider.dart'
    show fullBackupJobApiProvider, initialFullBackupJobPendingProvider;
import 'features/library/data/repositories/book_repository.dart';
import 'features/manga/data/services/ocr_background_worker.dart';
import 'features/manga/data/services/ocr_billing_client.dart';
import 'features/manga/data/services/ocr_store_service.dart';
import 'features/reader/data/services/mecab_service.dart';
import 'features/settings/data/services/app_settings_storage.dart';
import 'features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'features/settings/data/services/kanjivg_download_service.dart';

/// Global navigator key used by Sentry for feedback screenshots
/// and navigator observation.
final navigatorKey = GlobalKey<NavigatorState>();

/// Global scaffold messenger key so snackbars can be shown on top of
/// modal bottom sheets and other overlays.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Global Riverpod provider for the Drift database instance.
/// Created once at app startup and disposed when the app is torn down.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // Fill search_text for dictionary rows imported before schema v18 so
  // English glossary search covers them. Runs in a background isolate,
  // resumes if interrupted, and no-ops once complete.
  unawaited(
    db.backfillGlossarySearchText().catchError((Object e) {
      debugPrint('Glossary search-text backfill failed: $e');
    }),
  );
  ref.onDispose(() => db.close());
  return db;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap Flutter's image cache to reduce memory pressure on low-end devices.
  // Defaults are 1000 images / 100 MB which is excessive for a manga reader
  // where each decoded page can be several MB.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 50;

  final audience = await resolveSentryAudience();
  if (audience.isSynthetic) {
    AnalyticsService.instance.suppress();
  }

  await SentryFlutter.init((options) {
    applySharedSentryOptions(options, audience);
    options.navigatorKey = navigatorKey;
  }, appRunner: _bootApp);
}

/// Everything from the staged-restore check to the first frame. iOS runs it a
/// second time in the same process to apply a full restore
/// ([restartAppInProcess]).
Future<void> _bootApp() async {
  {
    {
      // Must run before anything opens the database: a staged full restore
      // swaps the database and books directory into place with renames.
      await applyStagedFullRestoreIfAny();
      // iOS moves the data container on reinstall; stored absolute paths
      // follow it here, still before the database opens.
      await reanchorLibraryIfMovedAtBoot();
      await PreloadedAppSettings.load();
      await PreloadedProEntitlement.load();
      // A job left by the previous process must block the app from the
      // first frame, before any poll answers.
      // iOS has no native job service: the job runs in this process.
      final iosFullBackupJob = Platform.isIOS
          ? await IosFullBackup.start()
          : null;
      final fullBackupJobPending = iosFullBackupJob == null
          ? await hasPendingFullBackupJob()
          : await hasPendingFullBackupJob(jobs: iosFullBackupJob);
      runApp(
        SentryWidget(
          child: ProviderScope(
            overrides: [
              initialFullBackupJobPendingProvider.overrideWithValue(
                fullBackupJobPending,
              ),
              if (iosFullBackupJob != null)
                fullBackupJobApiProvider.overrideWithValue(iosFullBackupJob),
            ],
            child: const MekuruApp(),
          ),
        ),
      );
      _scheduleDeferredStartupWarmups();
    }
  }
}

/// Applies a staged full restore without ending the process. iOS only: an app
/// that exits by itself reads as a crash there, to users and to App Review.
/// Unmounting the old tree disposes every provider, then the boot sequence
/// runs again from the top, as on a cold start. [db] is the database the old
/// tree used; the caller reads it from its provider before the tree goes.
Future<void> restartAppInProcess(AppDatabase db) async {
  // Leave the tap handler first: runApp's warm-up frame locks event dispatch,
  // and doing that in the middle of the tap trips a debug assertion.
  await Future<void>.delayed(Duration.zero);
  runApp(
    const ColoredBox(
      color: Color(0xFF000000),
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  // Only now: drift's close() waits for every open query stream, and a stream
  // whose listener is paused (the library sits offstage under the restore
  // page) never finishes, so closing before the unmount hangs for good. The
  // unmount cancelled them all. databaseProvider's onDispose has already
  // called close(); a second call waits for the same shutdown.
  await db.close();
  // Covers are cached by file path, and the restored library reuses paths.
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  await _bootApp();
}

void _scheduleDeferredStartupWarmups() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_runDeferredStartupWarmups());
  });
}

// Keep the first frame light. These services all lazily initialize on
// demand, so we can warm them after the UI is visible.
Future<void> _runDeferredStartupWarmups() => tracedOperation(
  'app.startup_warmup_duration_ms',
  action: () async {
    await _runStartupWarmup(
      step: 'firebase',
      action: FirebaseRuntime.instance.ensureFirebaseApp,
    );
    await Future.wait([
      _runStartupWarmup(
        step: 'ocr_flush',
        action: flushPendingOcrFinalizations,
      ),
      _runStartupWarmup(
        step: 'ocr_interrupted',
        action: resetInterruptedIosOcr,
      ),
      _runStartupWarmup(
        step: 'billing',
        // Also converges the local Play entitlement (grants it to legacy
        // buyers, revokes it after a refund).
        action: OcrStoreService.instance.syncOwnedPurchases,
      ),
      _runStartupWarmup(
        step: 'workmanager',
        action: () => Workmanager().initialize(ocrWorkerCallbackDispatcher),
      ),
      _runStartupWarmup(
        step: 'mecab',
        action: () async {
          await MecabService.instance.init();
          // The dictionary rides along as the mecab_dict tag.
          logUsage('mecab.initialized');
          // After init, so the IPADIC copy under Documents/assets exists.
          // Every launch: a restored unidic-lite dir arrives without the flag.
          final docs = await getApplicationDocumentsDirectory();
          final support = await getApplicationSupportDirectory();
          await excludeFromIosBackup([
            // A restored books dir also arrives without the flag.
            p.join(support.path, BookRepository.booksSegment),
            p.join(docs.path, 'assets'),
            await EnhancedFuriganaDictDownloadService.getStorageDir(),
            await KanjiVgDownloadService.getStorageDir(),
          ]);
        },
      ),
    ]);
  },
);

Future<void> _runStartupWarmup({
  required String step,
  required Future<void> Function() action,
}) async {
  try {
    await action();
  } catch (error, stackTrace) {
    logFailure(
      'app.startup_warmup_failed',
      error,
      stackTrace: stackTrace,
      attrs: {'step': step},
    );
  }
}
