import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/image_convert.dart';
import 'package:mekuru/features/reader/data/services/epub_image_zoom.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Full-screen viewer for an EPUB image, opened by a long press: the
/// [images] (two for a spread's halves, left first) side by side at one
/// height, fitted to the screen, pinch to zoom. A tap closes it. It buzzes
/// as it opens: a long press that finds nothing to show stays quiet.
class EpubImageZoomView extends StatefulWidget {
  const EpubImageZoomView({super.key, required this.images});

  final List<ZoomImage> images;

  @override
  State<EpubImageZoomView> createState() => _EpubImageZoomViewState();
}

class _EpubImageZoomViewState extends State<EpubImageZoomView> {
  @override
  void initState() {
    super.initState();
    AppHaptics.medium();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final height = images.map((i) => i.height).reduce(max).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        label: context.l10n.commonClose,
        button: true,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: FittedBox(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final image in images)
                      SizedBox(
                        width: image.width * height / image.height,
                        height: height,
                        child: Image(
                          image: fileImage(File(image.path)),
                          fit: BoxFit.fill,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
