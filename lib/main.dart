import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/database/database_provider.dart';
import 'core/services/analytics_service.dart';
import 'core/services/firebase_runtime.dart';
import 'core/services/sentry_helpers.dart';
import 'core/services/sentry_setup.dart';
import 'core/services/usage_telemetry.dart';
import 'features/manga/data/services/ocr_background_worker.dart';
import 'features/manga/data/services/ocr_billing_client.dart';
import 'features/manga/data/services/ocr_store_service.dart';
import 'features/reader/data/services/mecab_service.dart';
import 'features/settings/data/services/app_settings_storage.dart';

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

  await SentryFlutter.init(
    (options) {
      applySharedSentryOptions(options, audience);
      options.navigatorKey = navigatorKey;
    },
    appRunner: () async {
      await PreloadedAppSettings.load();
      await PreloadedProEntitlement.load();
      runApp(SentryWidget(child: const ProviderScope(child: MekuruApp())));
      _scheduleDeferredStartupWarmups();
    },
  );
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
