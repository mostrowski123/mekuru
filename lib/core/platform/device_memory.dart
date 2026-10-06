import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

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
