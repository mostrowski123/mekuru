import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/book_reading_config.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

void main() {
  group('bookSupportsVerticalText', () {
    test('returns true for Japanese', () {
      expect(bookSupportsVerticalText('ja'), isTrue);
    });

    test('returns true for Chinese', () {
      expect(bookSupportsVerticalText('zh'), isTrue);
    });

    test('returns true for Korean', () {
      expect(bookSupportsVerticalText('ko'), isTrue);
    });

    test('returns true for null (legacy books)', () {
      expect(bookSupportsVerticalText(null), isTrue);
    });

    test('returns false for English', () {
      expect(bookSupportsVerticalText('en'), isFalse);
    });

    test('returns false for French', () {
      expect(bookSupportsVerticalText('fr'), isFalse);
    });

    test('returns false for German', () {
      expect(bookSupportsVerticalText('de'), isFalse);
    });

    test('returns false for Spanish', () {
      expect(bookSupportsVerticalText('es'), isFalse);
    });

    test('is case-insensitive', () {
      expect(bookSupportsVerticalText('JA'), isTrue);
      expect(bookSupportsVerticalText('Zh'), isTrue);
      expect(bookSupportsVerticalText('EN'), isFalse);
    });
  });

  group('bookIsNaturallyRtl', () {
    test('returns true for Japanese with no ppd', () {
      expect(bookIsNaturallyRtl(language: 'ja'), isTrue);
    });

    test('returns false for English with no ppd', () {
      expect(bookIsNaturallyRtl(language: 'en'), isFalse);
    });

    test('returns true for null language (legacy books)', () {
      expect(bookIsNaturallyRtl(), isTrue);
    });

    test('returns false for Chinese with no ppd', () {
      expect(bookIsNaturallyRtl(language: 'zh'), isFalse);
    });

    test('explicit rtl ppd overrides English language', () {
      expect(
        bookIsNaturallyRtl(
          language: 'en',
          pageProgressionDirection: 'rtl',
        ),
        isTrue,
      );
    });

    test('explicit ltr ppd overrides Japanese language', () {
      expect(
        bookIsNaturallyRtl(
          language: 'ja',
          pageProgressionDirection: 'ltr',
        ),
        isFalse,
      );
    });

    test('ignores unknown ppd values and falls back to language', () {
      expect(
        bookIsNaturallyRtl(
          language: 'ja',
          pageProgressionDirection: 'default',
        ),
        isTrue,
      );
      expect(
        bookIsNaturallyRtl(
          language: 'en',
          pageProgressionDirection: 'default',
        ),
        isFalse,
      );
    });
  });

  group('defaultReaderDirection', () {
    test('Japanese book defaults to RTL', () {
      expect(
        defaultReaderDirection(language: 'ja'),
        ReaderDirection.rtl,
      );
    });

    test('English book defaults to LTR', () {
      expect(
        defaultReaderDirection(language: 'en'),
        ReaderDirection.ltr,
      );
    });

    test('null language defaults to RTL (legacy assumed Japanese)', () {
      expect(defaultReaderDirection(), ReaderDirection.rtl);
    });

    test('ppd overrides language default', () {
      expect(
        defaultReaderDirection(
          language: 'en',
          pageProgressionDirection: 'rtl',
        ),
        ReaderDirection.rtl,
      );
      expect(
        defaultReaderDirection(
          language: 'ja',
          pageProgressionDirection: 'ltr',
        ),
        ReaderDirection.ltr,
      );
    });
  });

  group('defaultVerticalText', () {
    test('Japanese book defaults to true', () {
      expect(defaultVerticalText(language: 'ja'), isTrue);
    });

    test('English book defaults to false', () {
      expect(defaultVerticalText(language: 'en'), isFalse);
    });

    test('null language defaults to true (legacy assumed Japanese)', () {
      expect(defaultVerticalText(), isTrue);
    });

    test('Japanese book with explicit ltr ppd defaults to false', () {
      expect(
        defaultVerticalText(
          language: 'ja',
          pageProgressionDirection: 'ltr',
        ),
        isFalse,
      );
    });

    test('Chinese book without rtl ppd defaults to false', () {
      // Chinese supports vertical text but is not naturally RTL by our logic
      expect(defaultVerticalText(language: 'zh'), isFalse);
    });

    test('Chinese book with rtl ppd defaults to true', () {
      expect(
        defaultVerticalText(
          language: 'zh',
          pageProgressionDirection: 'rtl',
        ),
        isTrue,
      );
    });

    test('English book with rtl ppd still returns false (no vertical support)',
        () {
      // English doesn't support vertical text even if ppd is rtl
      expect(
        defaultVerticalText(
          language: 'en',
          pageProgressionDirection: 'rtl',
        ),
        isFalse,
      );
    });
  });
}
