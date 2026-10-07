import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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

/// True when [bytes] open with an ISOBMFF `ftyp` box naming an AVIF brand
/// (`avif` for a still image, `avis` for a sequence), major or compatible.
bool isAvif(Uint8List bytes) {
  if (bytes.length < 16 || String.fromCharCodes(bytes, 4, 8) != 'ftyp') {
    return false;
  }
  final size = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  final end = size < bytes.length ? size : bytes.length;
  for (var i = 8; i + 4 <= end; i += 4) {
    if (i == 12) continue; // minor_version, not a brand
    final brand = String.fromCharCodes(bytes, i, i + 4);
    if (brand == 'avif' || brand == 'avis') return true;
  }
  return false;
}

/// Decodes [bytes] with [engine], Flutter's own codec, which reads AVIF only
/// on Android 12+ (through the platform ImageDecoder). AVIF the engine cannot
/// read (iOS, Android 7-11) is decoded on the platform side instead, to RGBA:
/// ImageIO on iOS, libavif on Android. Nothing is converted or stored.
// ponytail: the platform side hands back full-size RGBA, resized here; give
// `decodeRgba` a max size if grids of AVIF covers ever stutter.
Future<ui.Codec> decodeWithAvifFallback(
  Uint8List bytes,
  Future<ui.Codec> Function() engine, {
  int? targetWidth,
}) async {
  try {
    return await engine();
  } catch (_) {
    if (!isAvif(bytes)) rethrow;
  }
  final page = await _channel.invokeMapMethod<String, Object?>(
    'decodeRgba',
    bytes,
  );
  if (page == null) throw StateError('The AVIF image could not be decoded.');
  final width = page['width'] as int;
  final height = page['height'] as int;
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    page['rgba'] as Uint8List,
  );
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  try {
    return await descriptor.instantiateCodec(
      targetWidth: targetWidth != null && targetWidth < width
          ? targetWidth
          : null,
    );
  } finally {
    // As ui.instantiateImageCodecWithSize does: the codec still reads the
    // descriptor when it decodes a frame, so only the buffer goes here.
    buffer.dispose();
  }
}

/// The provider `Image.file(file, cacheWidth: …)` would use, except that an
/// AVIF file goes through [AvifFileImage]. Every other format gets exactly
/// `Image.file`'s provider, so its decoding and cache keys are unchanged.
ImageProvider fileImage(File file, {int? cacheWidth}) =>
    file.path.toLowerCase().endsWith('.avif')
    ? AvifFileImage(file, cacheWidth: cacheWidth)
    : ResizeImage.resizeIfNeeded(cacheWidth, null, FileImage(file));

/// A local AVIF file, decoded through [decodeWithAvifFallback] and scaled
/// down to [cacheWidth] like `Image.file`'s `cacheWidth` (never up).
@immutable
class AvifFileImage extends ImageProvider<AvifFileImage> {
  const AvifFileImage(this.file, {this.cacheWidth});

  final File file;
  final int? cacheWidth;

  @override
  Future<AvifFileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AvifFileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    AvifFileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadCodec(decode),
    scale: 1.0,
    debugLabel: file.path,
  );

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final bytes = await file.readAsBytes();
    final width = cacheWidth;
    return decodeWithAvifFallback(
      bytes,
      () async => decode(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (intrinsicWidth, _) =>
            width != null && width < intrinsicWidth
            ? ui.TargetImageSize(width: width)
            : const ui.TargetImageSize(),
      ),
      targetWidth: width,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AvifFileImage &&
      other.file.path == file.path &&
      other.cacheWidth == cacheWidth;

  @override
  int get hashCode => Object.hash(file.path, cacheWidth);

  @override
  String toString() => 'AvifFileImage("${file.path}", cacheWidth: $cacheWidth)';
}
