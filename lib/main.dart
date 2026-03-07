import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'config/environment_config.dart';
import 'core/database/database_provider.dart';
import 'core/services/firebase_runtime.dart';
import 'features/manga/data/services/ocr_background_worker.dart';
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
  ref.onDispose(() => db.close());
  return db;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn = EnvironmentConfig.sentryDsn;
      options.environment = EnvironmentConfig.sentryEnvironment;
      options.navigatorKey = navigatorKey;
    },
    appRunner: () async {
      await PreloadedAppSettings.load();
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

Future<void> _runDeferredStartupWarmups() async {
  // Keep the first frame light. These services all lazily initialize on
  // demand, so we can warm them after the UI is visible.
  await _runStartupWarmup(
    logMessage: 'Firebase unavailable during startup warmup',
    action: FirebaseRuntime.instance.ensureFirebaseApp,
  );

  await Future.wait([
    _runStartupWarmup(
      logMessage: 'OCR finalization flush failed',
      action: flushPendingOcrFinalizations,
    ),
    _runStartupWarmup(
      logMessage: 'OcrStoreService init failed',
      action: OcrStoreService.instance.initialize,
    ),
    _runStartupWarmup(
      logMessage: 'WorkManager init failed',
      action: () => Workmanager().initialize(ocrWorkerCallbackDispatcher),
    ),
    _runStartupWarmup(
      logMessage: 'MeCab init failed (app will continue)',
      action: () async {
        await MecabService.instance.init();
        Sentry.addBreadcrumb(
          Breadcrumb(message: 'MeCab initialized', category: 'app.init'),
        );
      },
    ),
  ]);
}

Future<void> _runStartupWarmup({
  required String logMessage,
  required Future<void> Function() action,
}) async {
  try {
    await action();
  } catch (error, stackTrace) {
    debugPrint('[APP] $logMessage: $error');
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}
