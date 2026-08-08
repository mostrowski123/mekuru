import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';

/// [ImageProvider] for images backed by Android SAF (`content://` URI or a
/// persisted tree grant + relative path).
///
/// Keyed by the source location, so decoded images land in the global
/// [ImageCache]: re-showing a page is a synchronous cache hit (no platform
/// read, no decode, no flash) and [precacheImage] works for SAF pages.
class AndroidSafImageProvider extends ImageProvider<AndroidSafImageProvider> {
  final String? uri;
  final String? treeUri;
  final String? relativePath;
  final double scale;

  const AndroidSafImageProvider({
    this.uri,
    this.treeUri,
    this.relativePath,
    this.scale = 1.0,
  }) : assert(
         (uri != null) || (treeUri != null && relativePath != null),
         'Provide either uri or (treeUri + relativePath)',
       );

  @override
  Future<AndroidSafImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AndroidSafImageProvider>(this);

  // obtainKey returns `this`, so the key passed here is this provider.
  @override
  ImageStreamCompleter loadImage(
    AndroidSafImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(decode),
      scale: scale,
      debugLabel: _location,
    );
  }

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final bytes = uri != null
        ? await AndroidSafService.readBytesFromUri(uri!)
        : await AndroidSafService.readBytesFromTreePath(
            treeUri!,
            relativePath!,
          );
    if (bytes == null || bytes.isEmpty) {
      // Evict the failed entry so a later rebuild can retry the read.
      PaintingBinding.instance.imageCache.evict(this);
      throw StateError('Could not read SAF image: $_location');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  String get _location => uri ?? '$treeUri/$relativePath';

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is AndroidSafImageProvider &&
        other.uri == uri &&
        other.treeUri == treeUri &&
        other.relativePath == relativePath &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(uri, treeUri, relativePath, scale);

  @override
  String toString() => 'AndroidSafImageProvider("$_location", scale: $scale)';
}

/// Displays an image backed by Android SAF (`content://` URI or tree path).
class AndroidSafImage extends StatelessWidget {
  final String? uri;
  final String? treeUri;
  final String? relativePath;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Alignment alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final int? cacheWidth;
  final int? cacheHeight;

  /// Keep showing the previous frame while a new one decodes, instead of
  /// blanking. Matters when [cacheWidth] changes as the image is resized.
  final bool gaplessPlayback;

  const AndroidSafImage({
    super.key,
    this.uri,
    this.treeUri,
    this.relativePath,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.cacheWidth,
    this.cacheHeight,
    this.gaplessPlayback = false,
  }) : assert(
         (uri != null) || (treeUri != null && relativePath != null),
         'Provide either uri or (treeUri + relativePath)',
       );

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        cacheHeight,
        AndroidSafImageProvider(
          uri: uri,
          treeUri: treeUri,
          relativePath: relativePath,
        ),
      ),
      fit: fit,
      filterQuality: filterQuality,
      alignment: alignment,
      gaplessPlayback: gaplessPlayback,
      errorBuilder:
          errorBuilder ??
          (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
