import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'config/environment_config.dart';
import 'core/config/app_flavor.dart';
import 'core/database/database_provider.dart';
import 'core/services/analytics_service.dart';
import 'core/services/firebase_runtime.dart';
import 'core/services/pii_scrubber.dart';
import 'core/services/synthetic_client.dart';
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

  // Detect install source to set Sentry environment.
  // Debug builds always use 'debug'; release builds distinguish Play Store
  // from sideload, with the parallel flavor getting its own bucket so its
  // App Check / Play Integrity errors don't mix with regular sideloads.
  // Emulators and cloud device farms otherwise blend into the sideload
  // bucket, which is a real audience (the GitHub APK). Their crashes and
  // product metrics are both misleading, so they report nothing at all.
  final (isPlayStore, isSynthetic) = await (
    _isPlayStoreInstall(),
    _detectSyntheticClient(),
  ).wait;

  final String sentryEnvironment;
  if (kDebugMode) {
    sentryEnvironment = 'debug';
  } else if (isPlayStore) {
    sentryEnvironment = 'play-store';
  } else {
    sentryEnvironment = kIsParallelBuild ? 'sideload-parallel' : 'sideload';
  }

  if (isSynthetic) {
    AnalyticsService.instance.suppress();
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = EnvironmentConfig.sentryDsn;
      options.environment = sentryEnvironment;
      options.navigatorKey = navigatorKey;
      // Silencing synthetic clients through the sample rates and signal
      // switches drops their payloads before Sentry assembles contexts,
      // breadcrumbs, and stack traces, and cannot miss a signal type the way
      // enumerating each `beforeSendX` hook would.
      options.enableLogs = !isSynthetic;
      options.enableMetrics = !isSynthetic;
      options.sampleRate = isSynthetic ? 0.0 : 1.0;
      options.tracesSampleRate = isSynthetic ? 0.0 : 0.1;
      // Strip device file paths (which can embed book file names) from
      // everything that leaves the device.
      options.beforeSend = scrubEvent;
      options.beforeSendLog = scrubLog;
    },
    appRunner: () async {
      await PreloadedAppSettings.load();
      await PreloadedProEntitlement.load();
      runApp(SentryWidget(child: const ProviderScope(child: MekuruApp())));
      _scheduleDeferredStartupWarmups();
    },
  );
}

Future<bool> _isPlayStoreInstall() async {
  if (kDebugMode) return false;
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.installerStore == 'com.android.vending';
}

/// Reads Android build properties to decide whether this install is an
/// emulator, cloud device farm, or bot rather than a real reader.
///
/// Fails open: if the platform lookup fails we assume a real user, because
/// dropping genuine telemetry is worse than keeping some noise.
Future<bool> _detectSyntheticClient() async {
  if (kDebugMode || !Platform.isAndroid) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return isSyntheticAndroidClient(
      isPhysicalDevice: info.isPhysicalDevice,
      fingerprint: info.fingerprint,
      hardware: info.hardware,
      product: info.product,
      model: info.model,
    );
  } catch (_) {
    return false;
  }
}

void _scheduleDeferredStartupWarmups() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_runDeferredStartupWarmups());
  });
}

Future<void> _runDeferredStartupWarmups() async {
  final sw = Stopwatch()..start();

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
        Sentry.logger.info(
          'MeCab initialized',
          attributes: {
            'category': SentryAttribute.string('app.init'),
            'dictionary': SentryAttribute.string(
              MecabService.instance.layout.label,
            ),
          },
        );
      },
    ),
  ]);

  sw.stop();
  Sentry.metrics.distribution(
    'app.startup_warmup_ms',
    sw.elapsedMilliseconds,
    unit: SentryMetricUnit.millisecond,
  );
}

Future<void> _runStartupWarmup({
  required String logMessage,
  required Future<void> Function() action,
}) async {
  try {
    await action();
  } catch (error, stackTrace) {
    // Keep the message static: exception text can embed file paths.
    Sentry.logger.warn(
      logMessage,
      attributes: {
        'category': SentryAttribute.string('app.init'),
        'error_type': SentryAttribute.string(error.runtimeType.toString()),
      },
    );
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}
