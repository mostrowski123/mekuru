/// Sentry setup shared by the main isolate (`main.dart`) and background
/// isolates that run without it (the WorkManager OCR worker).
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../config/environment_config.dart';
import '../config/app_flavor.dart';
import 'pii_scrubber.dart';
import 'synthetic_client.dart';

/// Which reporting bucket this install belongs to, and whether it is a real
/// reader at all.
typedef SentryAudience = ({String environment, bool isSynthetic});

/// Debug builds always use 'debug'; release builds distinguish Play Store
/// from sideload, with the parallel flavor getting its own bucket so its
/// App Check / Play Integrity errors don't mix with regular sideloads.
/// Emulators and cloud device farms otherwise blend into the sideload
/// bucket, which is a real audience (the GitHub APK). Their crashes and
/// product metrics are both misleading, so callers report nothing for them.
Future<SentryAudience> resolveSentryAudience() async {
  final (isPlayStore, isSynthetic) = await (
    _isPlayStoreInstall(),
    _detectSyntheticClient(),
  ).wait;

  final String environment;
  if (kDebugMode) {
    environment = 'debug';
  } else if (isPlayStore) {
    environment = 'play-store';
  } else {
    environment = kIsParallelBuild ? 'sideload-parallel' : 'sideload';
  }
  return (environment: environment, isSynthetic: isSynthetic);
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

/// Options every isolate's hub must agree on — above all the PII scrub
/// hooks, which are the privacy guarantee this app documents.
void applySharedSentryOptions(SentryOptions options, SentryAudience audience) {
  options.dsn = EnvironmentConfig.sentryDsn;
  options.environment = audience.environment;
  // Silencing synthetic clients through the sample rates and signal
  // switches drops their payloads before Sentry assembles contexts,
  // breadcrumbs, and stack traces, and cannot miss a signal type the way
  // enumerating each `beforeSendX` hook would.
  final report = !audience.isSynthetic;
  options.enableLogs = report;
  options.enableMetrics = report;
  options.sampleRate = report ? 1.0 : 0.0;
  options.tracesSampleRate = report ? 0.1 : 0.0;
  // Strip device file paths (which can embed book file names) from
  // everything that leaves the device.
  options.beforeSend = scrubEvent;
  options.beforeSendLog = scrubLog;
}

/// Gives a background isolate its own Sentry hub. Dart globals are
/// per-isolate, so without this every `logUsage`, `logFailure` and
/// `captureException` in the isolate is a silent no-op.
///
/// Dart-only on purpose: `SentryFlutter.init` would re-initialize — and the
/// isolate's `Sentry.close` would then shut down — the process-wide native
/// SDK the main isolate owns. Never throws: an isolate must finish its real
/// work whether or not it can report.
Future<void> initSentryForBackgroundIsolate() async {
  try {
    if (EnvironmentConfig.sentryDsn.isEmpty) return;
    final audience = await resolveSentryAudience();
    if (audience.isSynthetic) return;
    final info = await PackageInfo.fromPlatform();
    await Sentry.init((options) {
      applySharedSentryOptions(options, audience);
      options.release =
          '${info.packageName}@${info.version}+${info.buildNumber}';
      options.dist = info.buildNumber;
    });
  } catch (error) {
    debugPrint('[Sentry] background init skipped: ${error.runtimeType}');
  }
}
