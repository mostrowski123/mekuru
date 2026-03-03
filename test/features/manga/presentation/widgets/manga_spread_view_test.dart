import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';

void main() {
  group('resolveSpreadAutoCropTargetHeight', () {
    test('uses the taller fitted crop height across both pages', () {
      final leftPage = MokuroPage(
        pageIndex: 0,
        imageFileName: 'left.png',
        imgWidth: 120,
        imgHeight: 240,
        blocks: const [],
        contentBounds: Rect.fromLTRB(10, 10, 90, 170),
      );
      final rightPage = MokuroPage(
        pageIndex: 1,
        imageFileName: 'right.png',
        imgWidth: 120,
        imgHeight: 240,
        blocks: const [],
        contentBounds: Rect.fromLTRB(20, 20, 100, 140),
      );

      expect(
        resolveSpreadAutoCropTargetHeight(
          leftPage,
          rightPage,
          containerWidth: 100,
          containerHeight: 200,
        ),
        closeTo(200, 0.0001),
      );
    });

    test('returns null when either page is missing crop bounds', () {
      final leftPage = MokuroPage(
        pageIndex: 0,
        imageFileName: 'left.png',
        imgWidth: 120,
        imgHeight: 240,
        blocks: const [],
      );
      final rightPage = MokuroPage(
        pageIndex: 1,
        imageFileName: 'right.png',
        imgWidth: 120,
        imgHeight: 240,
        blocks: const [],
        contentBounds: Rect.fromLTRB(20, 20, 100, 140),
      );

      expect(
        resolveSpreadAutoCropTargetHeight(
          leftPage,
          rightPage,
          containerWidth: 100,
          containerHeight: 200,
        ),
        isNull,
      );
    });
  });
}
