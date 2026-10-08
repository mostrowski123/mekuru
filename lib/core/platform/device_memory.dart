import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

/// Replaces the device check in tests, whatever the thresholds.
@visibleForTesting
bool? debugDeviceLowOnMemory;

/// Whether this Android phone may struggle with extra memory: Android's own
/// low-RAM flag, a phone with under [minTotalMb] of RAM, or under
/// [minFreeMb] free right now. The defaults suit Standard sentence
/// translation (a few hundred MB). High quality passes 7168 / 3072 (phones
/// sold with 8 GB). False on other platforms and when the check fails.
Future<bool> deviceLowOnMemory({
  int minTotalMb = 3584,
  int minFreeMb = 600,
}) async {
  final override = debugDeviceLowOnMemory;
  if (override != null) return override;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    // Android reports RAM less the kernel's share, so a phone sold as 4 GB
    // shows about 3.6-3.8 GB: 3.5 GB is the line under it.
    return info.isLowRamDevice ||
        info.physicalRamSize < minTotalMb ||
        info.availableRamSize < minFreeMb;
  } catch (_) {
    return false;
  }
}

const _processExitChannel = MethodChannel('mekuru/process_exit');

/// Once per launch (Android): tags usage with the device's RAM in whole GB
/// (`ram_band`, so `session.summary` can be split by it) and logs why the
/// previous process ended (`app.previous_exit`). Low-memory kills in the
/// background never reach Sentry otherwise. Native answers the exit once per
/// process, so running this again logs nothing new. Does nothing on iOS.
Future<void> reportMemoryAtLaunch() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    setUsageTag('ram_band', ramBand(info.physicalRamSize));
    final exit = await _processExitChannel.invokeMapMethod<String, int>(
      'previousExit',
    );
    if (exit == null) return;
    logUsage(
      'app.previous_exit',
      attrs: {
        'reason': processExitReasonName(exit['reason'] ?? 0),
        // ActivityManager.RunningAppProcessInfo: 100 foreground, 125 a
        // foreground service, 200 visible, 400 cached (in the background).
        'importance': exit['importance'] ?? 0,
      },
    );
  } catch (_) {
    // Telemetry only.
  }
}

/// Total RAM in whole GB, as the device is sold: Android reports it less the
/// kernel's share (a 4 GB phone shows about 3.6-3.8 GB), so it rounds up.
@visibleForTesting
String ramBand(int physicalRamMb) => '${(physicalRamMb / 1024).ceil()}';

/// `ApplicationExitInfo.REASON_*` by value (Android 11-14).
const _exitReasons = [
  'unknown',
  'exit_self',
  'signaled',
  'low_memory',
  'crash',
  'crash_native',
  'anr',
  'initialization_failure',
  'permission_change',
  'excessive_resource_usage',
  'user_requested',
  'user_stopped',
  'dependency_died',
  'other',
  'freezer',
  'package_state_change',
  'package_updated',
];

/// The name of an `ApplicationExitInfo` reason; the number itself for one
/// newer than this list.
@visibleForTesting
String processExitReasonName(int reason) =>
    reason >= 0 && reason < _exitReasons.length
    ? _exitReasons[reason]
    : '$reason';
