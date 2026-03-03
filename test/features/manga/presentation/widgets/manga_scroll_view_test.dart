import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_scroll_view.dart';

void main() {
  group('resolveScrollPageAspectRatio', () {
    final page = MokuroPage(
      pageIndex: 0,
      imageFileName: 'page.png',
      imgWidth: 120,
      imgHeight: 240,
      blocks: const [],
      contentBounds: Rect.fromLTRB(20, 10, 80, 110),
    );

    test('uses cropped bounds when auto-crop is enabled', () {
      expect(
        resolveScrollPageAspectRatio(page, autoCrop: true),
        closeTo(0.6, 0.0001),
      );
    });

    test(
      'falls back to the full image dimensions when auto-crop is disabled',
      () {
        expect(
          resolveScrollPageAspectRatio(page, autoCrop: false),
          closeTo(0.5, 0.0001),
        );
      },
    );
  });
}
