import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

const mangaBackdropGray = Color(0xFF424242);

/// The most common colour on the outer ring of pixels of a premultiplied
/// RGBA image, as it looks over black. Most common, not the mean: a panel
/// that bleeds off the page must not tint a white margin gray.
Color edgeColorFromRgba(ByteData rgba, int width, int height) {
  // Near-identical colours share a bucket: [count, red, green, blue] sums.
  final buckets = <int, List<int>>{};
  List<int>? best;
  for (var y = 0; y < height; y++) {
    // Top and bottom rows in full, only the two ends of the rows between.
    final everyPixel = y == 0 || y == height - 1 || width == 1;
    for (var x = 0; x < width; x += everyPixel ? 1 : width - 1) {
      final i = (y * width + x) * 4;
      final r = rgba.getUint8(i);
      final g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      final bucket = buckets.putIfAbsent(
        (r >> 4) << 8 | (g >> 4) << 4 | b >> 4,
        () => [0, 0, 0, 0],
      );
      bucket[0]++;
      bucket[1] += r;
      bucket[2] += g;
      bucket[3] += b;
      if (best == null || bucket[0] > best[0]) best = bucket;
    }
  }
  if (best == null) return Colors.black;
  final count = best[0];
  return Color.fromARGB(
    255,
    (best[1] / count).round(),
    (best[2] / count).round(),
    (best[3] / count).round(),
  );
}

/// What the manga reader shows around the page. [pageImage] is the page on
/// screen, at any size; only [MangaBackground.auto] and
/// [MangaBackground.blur] load it.
class MangaBackdrop extends StatefulWidget {
  const MangaBackdrop({super.key, required this.mode, this.pageImage});

  final MangaBackground mode;
  final ImageProvider? pageImage;

  @override
  State<MangaBackdrop> createState() => _MangaBackdropState();
}

class _MangaBackdropState extends State<MangaBackdrop> {
  late final _listener = ImageStreamListener(
    _onPageImage,
    // An unreadable page has nothing of its own to show: plain black.
    onError: (_, _) => _showBlack(),
  );
  ImageStream? _stream;

  /// The page a few pixels wide and blurred once, here: stretched over the
  /// screen it is the Blur background, with no filter running per frame.
  ui.Image? _blurred;
  Color _edgeColor = Colors.black;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenToPage();
  }

  @override
  void didUpdateWidget(MangaBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listenToPage();
  }

  void _listenToPage() {
    final usesPage =
        widget.mode == MangaBackground.auto ||
        widget.mode == MangaBackground.blur;
    final stream = usesPage
        ? widget.pageImage?.resolve(createLocalImageConfiguration(context))
        : null;
    if (stream?.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream?..addListener(_listener);
  }

  void _onPageImage(ImageInfo info, bool _) {
    // At most 32 px wide, whatever size the reader decoded the page at.
    final page = info.image;
    final width = math.min(page.width, 32);
    final thumbnail = _redraw(
      page,
      width,
      math.max(1, page.height * width ~/ page.width),
    );
    info.dispose();
    final blurred = _redraw(
      thumbnail,
      thumbnail.width,
      thumbnail.height,
      // Clamp: the default fades to nothing at the border.
      filter: ui.ImageFilter.blur(
        sigmaX: 2,
        sigmaY: 2,
        tileMode: TileMode.clamp,
      ),
    );
    _blurred?.dispose();
    setState(() => _blurred = blurred);
    unawaited(_readEdgeColor(thumbnail, blurred));
  }

  void _showBlack() {
    _blurred?.dispose();
    setState(() {
      _blurred = null;
      _edgeColor = Colors.black;
    });
  }

  /// The edge colour comes from the unblurred [thumbnail], which this
  /// disposes.
  Future<void> _readEdgeColor(ui.Image thumbnail, ui.Image blurred) async {
    final (width, height) = (thumbnail.width, thumbnail.height);
    final ByteData? data;
    try {
      data = await thumbnail.toByteData();
    } catch (_) {
      // The pixels could not be read: the colour stays as it was.
      return;
    } finally {
      thumbnail.dispose();
    }
    // A later page may have replaced this one while its pixels were read.
    if (!mounted || blurred != _blurred || data == null) return;
    final color = edgeColorFromRgba(data, width, height);
    setState(() => _edgeColor = color);
  }

  static ui.Image _redraw(
    ui.Image source,
    int width,
    int height, {
    ui.ImageFilter? filter,
  }) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Offset.zero & Size(source.width.toDouble(), source.height.toDouble()),
      Offset.zero & Size(width.toDouble(), height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = filter,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _blurred?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.mode) {
    MangaBackground.black => const ColoredBox(color: Colors.black),
    MangaBackground.gray => const ColoredBox(color: mangaBackdropGray),
    MangaBackground.white => const ColoredBox(color: Colors.white),
    MangaBackground.auto => ColoredBox(color: _edgeColor),
    // Stretched to the screen, so each margin carries the colours of the
    // page edge next to it.
    MangaBackground.blur => ColoredBox(
      color: Colors.black,
      child: RawImage(
        image: _blurred,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      ),
    ),
  };
}
