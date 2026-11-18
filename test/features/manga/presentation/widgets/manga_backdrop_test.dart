import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_backdrop.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import '../../../../shared/saf_image_fixtures.dart';

/// 4x4 premultiplied RGBA: [ring] on the 12 outer pixels, [centre] inside.
ByteData _rgba4x4({required List<int> ring, required List<int> centre}) {
  final data = ByteData(4 * 4 * 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final pixel = x == 0 || x == 3 || y == 0 || y == 3 ? ring : centre;
      for (var c = 0; c < 4; c++) {
        data.setUint8((y * 4 + x) * 4 + c, pixel[c]);
      }
    }
  }
  return data;
}

/// A page image the test finishes, or fails, by hand.
class _Page extends ImageProvider<_Page> {
  final loaded = Completer<ImageInfo>();
  var loads = 0;

  @override
  Future<_Page> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Page key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(loaded.future);
  }
}

Future<ImageInfo> _solid(WidgetTester tester, int r, int g, int b) async {
  final image = await tester.runAsync(() {
    final pixel = [r, g, b, 255];
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _rgba4x4(ring: pixel, centre: pixel).buffer.asUint8List(),
      4,
      4,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  });
  return ImageInfo(image: image!);
}

Widget _host(MangaBackground mode, [ImageProvider? page]) => Directionality(
  textDirection: TextDirection.ltr,
  child: MangaBackdrop(mode: mode, pageImage: page),
);

Color _colour(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(MangaBackdrop),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  tearDown(() {
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  group('edgeColorFromRgba', () {
    test('is the ring, not the centre', () {
      final data = _rgba4x4(ring: [255, 0, 0, 255], centre: [0, 0, 255, 255]);
      expect(edgeColorFromRgba(data, 4, 4), const Color(0xFFFF0000));
    });

    test('a panel that bleeds off the page does not tint a white margin', () {
      final data = _rgba4x4(
        ring: [255, 255, 255, 255],
        centre: [0, 0, 255, 255],
      );
      // Three of the twelve ring pixels are black ink.
      for (final i in [0, 1, 2]) {
        data.setUint32(i * 4, 0x000000FF);
      }
      expect(edgeColorFromRgba(data, 4, 4), const Color(0xFFFFFFFF));
    });

    test('reads a transparent ring as black, never transparent', () {
      final data = _rgba4x4(ring: [0, 0, 0, 0], centre: [255, 255, 255, 255]);
      expect(edgeColorFromRgba(data, 4, 4), const Color(0xFF000000));
    });

    test('is black for an empty image', () {
      expect(edgeColorFromRgba(ByteData(0), 0, 0), const Color(0xFF000000));
    });
  });

  testWidgets('flat choices paint their colour and never load the page', (
    tester,
  ) async {
    final page = _Page();
    for (final (mode, colour) in [
      (MangaBackground.black, Colors.black),
      (MangaBackground.gray, mangaBackdropGray),
      (MangaBackground.white, Colors.white),
    ]) {
      await tester.pumpWidget(_host(mode, page));
      expect(_colour(tester), colour, reason: mode.name);
    }
    expect(page.loads, 0);
  });

  testWidgets('auto takes the page edge colour', (tester) async {
    final page = _Page();
    await tester.pumpWidget(_host(MangaBackground.auto, page));
    expect(_colour(tester), Colors.black);

    page.loaded.complete(await _solid(tester, 0x11, 0x22, 0x33));
    await pumpUntil(tester, () => _colour(tester) == const Color(0xFF112233));
  });

  testWidgets('auto keeps the newer page when an older one finishes late', (
    tester,
  ) async {
    final older = _Page(), newer = _Page();
    await tester.pumpWidget(_host(MangaBackground.auto, older));
    await tester.pumpWidget(_host(MangaBackground.auto, newer));

    newer.loaded.complete(await _solid(tester, 0, 0, 255));
    await pumpUntil(tester, () => _colour(tester) == const Color(0xFF0000FF));

    older.loaded.complete(await _solid(tester, 255, 0, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(_colour(tester), const Color(0xFF0000FF));
  });

  testWidgets('auto and blur stay black when the page cannot be read', (
    tester,
  ) async {
    for (final mode in [MangaBackground.auto, MangaBackground.blur]) {
      final page = _Page();
      await tester.pumpWidget(_host(mode, page));
      page.loaded.completeError(Exception('page file is gone'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(_colour(tester), Colors.black, reason: mode.name);
      expect(tester.takeException(), isNull, reason: mode.name);
    }
  });

  testWidgets('a page that cannot be read does not keep the one before it', (
    tester,
  ) async {
    final first = _Page(), broken = _Page();
    await tester.pumpWidget(_host(MangaBackground.auto, first));
    first.loaded.complete(await _solid(tester, 0, 0, 255));
    await pumpUntil(tester, () => _colour(tester) == const Color(0xFF0000FF));

    await tester.pumpWidget(_host(MangaBackground.auto, broken));
    broken.loaded.completeError(Exception('page file is gone'));
    await pumpUntil(tester, () => _colour(tester) == Colors.black);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blur fills the screen with the page, right up to the edge', (
    tester,
  ) async {
    final page = _Page();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: _host(MangaBackground.blur, page)),
    );
    page.loaded.complete(await _solid(tester, 255, 255, 255));
    await tester.pump(); // the image arrives
    await tester.pump(); // and is painted

    // Black shows wherever the page does not reach; a blur filter that
    // fades out at its border would darken the corner too.
    final cornerRed = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = (await image.toByteData())!;
      image.dispose();
      return data.getUint8(0);
    });
    expect(cornerRed, greaterThan(250));
  });

  testWidgets('blur without a page is plain black', (tester) async {
    await tester.pumpWidget(_host(MangaBackground.blur));
    expect(_colour(tester), Colors.black);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
  });
}
