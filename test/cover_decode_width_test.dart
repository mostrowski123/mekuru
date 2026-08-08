import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/presentation/widgets/book_cover_image.dart';

void main() {
  test('nearby widths share a decode width so resizing reuses the cache', () {
    // The folder hero flight resizes a cover continuously; every distinct
    // decode width is a fresh cache entry and a blank frame.
    final widths = [100.0, 101.0, 110.0, 125.0];
    final decoded = widths.map((w) => coverDecodeWidth(w, 3)).toSet();
    expect(decoded, hasLength(1));
  });

  test('decode width covers the requested size and is bucketed', () {
    expect(coverDecodeWidth(120, 3), 384); // 360 -> next 128 bucket
    expect(coverDecodeWidth(128, 1), 128); // exact bucket stays put
    expect(coverDecodeWidth(129, 1), 256);
    for (final width in [10.0, 60.0, 120.0, 400.0]) {
      expect(
        coverDecodeWidth(width, 3),
        greaterThanOrEqualTo((width * 3).ceil()),
        reason: 'must not decode below the laid-out size',
      );
    }
  });

  test('tiny and huge sizes stay in range', () {
    expect(coverDecodeWidth(0, 3), 128);
    expect(coverDecodeWidth(5000, 4), lessThanOrEqualTo(4096));
  });
}
