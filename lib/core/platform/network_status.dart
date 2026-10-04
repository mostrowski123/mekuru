import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

const _iosChannel = MethodChannel('mekuru/network');

/// Whether a large download can start without asking about mobile data. On
/// Android the active network is Wi-Fi; on iOS it is neither cellular or a
/// hotspot nor in Low Data Mode. False when the check fails, so callers ask
/// rather than spend the user's data.
Future<bool> isOnWifi() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _iosChannel.invokeMethod<bool>('isUnmetered') ?? false;
    }
    return await LocalMangaOcr.isWifiConnected();
  } catch (e, st) {
    logFailure('network.wifi_check_failed', e, stackTrace: st);
    return false;
  }
}
