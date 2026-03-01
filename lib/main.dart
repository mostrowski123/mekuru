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

  // Best-effort startup initialization. OCR flows can lazily initialize Firebase
  // later if startup auth is unavailable.
  try {
    await FirebaseRuntime.instance.ensureFirebaseApp();
  } catch (error, stackTrace) {
    debugPrint('[APP] Firebase unavailable during startup: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await flushPendingOcrFinalizations();
  } catch (e, st) {
    debugPrint('[APP] OCR finalization flush failed: $e');
    Sentry.captureException(e, stackTrace: st);
  }
  try {
    await OcrStoreService.instance.initialize();
  } catch (e, st) {
    debugPrint('[APP] OcrStoreService init failed: $e');
    Sentry.captureException(e, stackTrace: st);
  }

  // Initialize WorkManager for background OCR processing
  await Workmanager().initialize(ocrWorkerCallbackDispatcher);

  await SentryFlutter.init(
    (options) {
      options.dsn = EnvironmentConfig.sentryDsn;
      options.environment = EnvironmentConfig.sentryEnvironment;
      options.navigatorKey = navigatorKey;
    },
    appRunner: () async {
      await PreloadedAppSettings.load();

      try {
        await MecabService.instance.init();
        Sentry.addBreadcrumb(
          Breadcrumb(message: 'MeCab initialized', category: 'app.init'),
        );
      } catch (e, st) {
        debugPrint('[APP] MeCab init failed (app will continue): $e');
        Sentry.captureException(e, stackTrace: st);
      }

      runApp(SentryWidget(child: const ProviderScope(child: MekuruApp())));
    },
  );
}
