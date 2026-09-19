import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Overlay style for the immersive reader screens: light icons over the
/// black gradient control bars, no contrast scrims.
const SystemUiOverlayStyle readerSystemBarsOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const _systemUiChannel = MethodChannel('mekuru/android_system_ui');

/// Shows or hides the system bars for immersive reading: the status and
/// navigation bars on Android, the status bar and home indicator on iOS.
Future<void> setReaderSystemBarsVisible(bool visible) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
    return;
  }
  if (defaultTargetPlatform != TargetPlatform.android) return;

  try {
    await _systemUiChannel.invokeMethod<void>('setSystemBarsVisible', {
      'visible': visible,
    });
  } catch (_) {
    // Best effort only; the reader still works if the native host declines
    // the request on a non-Android platform or older embedder.
  }
}
