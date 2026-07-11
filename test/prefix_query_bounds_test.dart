import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/services/prefix_query_bounds.dart';

void main() {
  group('prefixUpperBound', () {
    test('increments the last code point for ASCII', () {
      expect(prefixUpperBound('abc'), 'abd');
    });

    test('increments the last code point for kana', () {
      // か (U+304B) → が (U+304C)
      expect(prefixUpperBound('にほんか'), 'にほんが');
    });

    test('increments the last code point for kanji', () {
      // 本 (U+672C) → 札 (U+672D)
      expect(prefixUpperBound('日本'), '日札');
    });

    test('skips the surrogate gap', () {
      // U+D7FF + 1 must land on U+E000 — surrogates are not valid scalars.
      expect(prefixUpperBound('퟿'), '');
    });

    test(
      'drops a trailing U+10FFFF and increments the previous code point',
      () {
        // あ (U+3042) → ぃ (U+3043)
        expect(prefixUpperBound('あ\u{10FFFF}'), 'ぃ');
      },
    );

    test('handles astral (surrogate-pair) code points', () {
      // 𩸽 (U+29E3D) → U+29E3E
      expect(prefixUpperBound('𩸽'), String.fromCharCode(0x29E3E));
    });

    test('returns null when no bound exists', () {
      expect(prefixUpperBound(''), isNull);
      expect(prefixUpperBound('\u{10FFFF}'), isNull);
    });
  });

  group('prefixSearchVariants', () {
    test('returns just the term for Japanese input', () {
      expect(prefixSearchVariants('日本'), ['日本']);
    });

    test('adds case variants for ASCII input', () {
      expect(prefixSearchVariants('dvd'), containsAll(['dvd', 'DVD', 'Dvd']));
    });

    test('deduplicates variants', () {
      final variants = prefixSearchVariants('DVD');
      expect(variants.toSet().length, variants.length);
      expect(variants, contains('DVD'));
      expect(variants, contains('dvd'));
    });

    test('handles mixed Japanese-ASCII input', () {
      // Tシャツ-style terms: case variants only touch the ASCII letters.
      expect(prefixSearchVariants('tシャツ'), contains('Tシャツ'));
    });
  });
}
