import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';

/// Displays an image backed by Android SAF (`content://` URI or tree path).
class AndroidSafImage extends StatefulWidget {
  final String? uri;
  final String? treeUri;
  final String? relativePath;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Alignment alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final int? cacheWidth;
  final int? cacheHeight;

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
  }) : assert(
         (uri != null) || (treeUri != null && relativePath != null),
         'Provide either uri or (treeUri + relativePath)',
       );

  @override
  State<AndroidSafImage> createState() => _AndroidSafImageState();
}

class _AndroidSafImageState extends State<AndroidSafImage> {
  late Future<Uint8List?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant AndroidSafImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.treeUri != widget.treeUri ||
        oldWidget.relativePath != widget.relativePath) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List?> _loadBytes() {
    if (widget.uri != null) {
      return AndroidSafService.readBytesFromUri(widget.uri!);
    }
    return AndroidSafService.readBytesFromTreePath(
      widget.treeUri!,
      widget.relativePath!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
            alignment: widget.alignment,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
            gaplessPlayback: true,
            errorBuilder: widget.errorBuilder,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final errorBuilder = widget.errorBuilder;
        if (errorBuilder != null) {
          return errorBuilder(
            context,
            snapshot.error ?? Exception('Failed to load image'),
            null,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
