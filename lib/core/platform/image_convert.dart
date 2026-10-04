import 'package:flutter/services.dart';

const _channel = MethodChannel('mekuru/image_convert');

/// Re-encodes an image Flutter cannot decode on iOS (AVIF) as PNG with
/// UIImage. Returns null when iOS cannot decode it either. iOS only: on
/// Android, Flutter already decodes AVIF through the platform ImageDecoder.
Future<Uint8List?> convertImageToPng(Uint8List bytes) async {
  try {
    return await _channel.invokeMethod<Uint8List>('toPng', bytes);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
