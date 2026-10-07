/// Sentry setup shared by the main isolate (`main.dart`) and background
/// isolates that run without it (the WorkManager OCR worker).
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../config/environment_config.dart';
import '../config/app_flavor.dart';
import 'pii_scrubber.dart';
import 'synthetic_client.dart';
import 'usage_telemetry.dart';

/// Which reporting bucket this install belongs to, and whether it is a real
/// reader at all.
typedef SentryAudience = ({String environment, bool isSynthetic});

/// Debug builds always use 'debug'; release builds are bucketed by where the
/// install came from (see [sentryEnvironmentForInstaller]).
/// Emulators and cloud device farms otherwise blend into the sideload
/// bucket, which is a real audience (the GitHub APK). Their crashes and
/// product metrics are both misleading, so callers report nothing for them.
Future<SentryAudience> resolveSentryAudience() async {
  final (installerStore, isSynthetic) = await (
    _installerStore(),
    _detectSyntheticClient(),
  ).wait;

  return (
    environment: kDebugMode
        ? 'debug'
        : sentryEnvironmentForInstaller(installerStore),
    isSynthetic: isSynthetic,
  );
}

/// Release-build environment for an install. Every iOS install is `ios`:
/// `package_info_plus` reports `com.apple` (App Store), `com.apple.testflight`
/// or `com.apple.simulator` there, and TestFlight and the App Store ship the
/// same binary. Anything else is a sideload, with the parallel flavor getting
/// its own bucket so its App Check / Play Integrity errors don't mix with
/// regular sideloads.
@visibleForTesting
String sentryEnvironmentForInstaller(String? installerStore) =>
    switch (installerStore) {
      'com.android.vending' => 'play-store',
      final store? when store.startsWith('com.apple') => 'ios',
      _ => kIsParallelBuild ? 'sideload-parallel' : 'sideload',
    };

Future<String?> _installerStore() async {
  if (kDebugMode) return null;
  return (await PackageInfo.fromPlatform()).installerStore;
}

/// Reads the platform's build properties to decide whether this install is
/// an emulator, simulator, cloud device farm, or bot rather than a real
/// reader.
///
/// Fails open: if the platform lookup fails we assume a real user, because
/// dropping genuine telemetry is worse than keeping some noise.
Future<bool> _detectSyntheticClient() async {
  if (kDebugMode) return false;
  try {
    if (Platform.isIOS) {
      return !(await DeviceInfoPlugin().iosInfo).isPhysicalDevice;
    }
    if (!Platform.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    if (isSyntheticAndroidClient(
      isPhysicalDevice: info.isPhysicalDevice,
      fingerprint: info.fingerprint,
      hardware: info.hardware,
      product: info.product,
      model: info.model,
    )) {
      return true;
    }
    // Play's pre-launch report devices pass as retail phones (a
    // "OnePlus8Pro"); only Test Lab's own flag gives them away. Background
    // isolates have no MainActivity channel: that throws, and fails open.
    return await const MethodChannel(
          'mekuru/test_lab',
        ).invokeMethod<bool>('isFirebaseTestLab') ??
        false;
  } catch (_) {
    return false;
  }
}

/// Options every isolate's hub must agree on — above all the PII scrub
/// hooks, which are the privacy guarantee this app documents.
void applySharedSentryOptions(SentryOptions options, SentryAudience audience) {
  // An empty DSN disables the Dart and the native SDK alike. Sample rates
  // can't silence synthetic clients: `sampleRate` never reaches the Android
  // SDK, which went on reporting their NDK crashes (MEKURU-26).
  options.dsn = audience.isSynthetic ? '' : EnvironmentConfig.sentryDsn;
  options.environment = audience.environment;
  options.enableLogs = true;
  options.enableMetrics = true;
  options.tracesSampleRate = 0.1;
  // Strip device file paths (which can embed book file names) from
  // everything that leaves the device. A crash on the user's side (a full
  // disk) is no issue of Mekuru's: it is logged as one instead.
  options.beforeSend = (event, hint) {
    final error = event.throwable;
    if (!isUserSideFailure(error)) return scrubEvent(event, hint);
    logFailure('app.user_side_error', error);
    return null;
  };
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
