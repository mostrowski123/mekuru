import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Replaces the device check in tests.
@visibleForTesting
bool? debugDeviceLowOnMemory;

/// Whether this Android phone may struggle with a few hundred MB of extra
/// memory (the sentence translation engine): Android's own low-RAM flag,
/// a phone sold with under 4 GB, or under 600 MB free right now. False on
/// other platforms and when the check fails.
Future<bool> deviceLowOnMemory() async {
  final override = debugDeviceLowOnMemory;
  if (override != null) return override;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    // Android reports RAM less the kernel's share, so a phone sold as 4 GB
    // shows about 3.6-3.8 GB: 3.5 GB is the line under it.
    return info.isLowRamDevice ||
        info.physicalRamSize < 3584 ||
        info.availableRamSize < 600;
  } catch (_) {
    return false;
  }
}
