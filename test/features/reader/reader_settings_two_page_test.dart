import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'two-page EPUB is off until switched on, then saved and backed up',
    () async {
      expect(const ReaderSettings().epubTwoPage, isFalse);
      SharedPreferences.setMockInitialValues({'reader.font_size': 24.0});
      final storage = SharedPreferencesReaderSettingsStorage();
      expect((await storage.load())!.epubTwoPage, isFalse);

      await storage.save(const ReaderSettings(epubTwoPage: true));
      expect((await storage.load())!.epubTwoPage, isTrue);
      expect(
        SharedPreferencesReaderSettingsStorage.allKeys,
        contains('reader.epub_two_page'),
      );
    },
  );

  test('two pages are offered only when switched on and paginated', () {
    const on = ReaderSettings(epubTwoPage: true);
    const off = ReaderSettings();
    // Tablets, unfolded foldables and phones held sideways are this wide; a
    // phone held upright is not. The page applies it to its own width.
    expect(
      epubTwoPageMinWidth(twoPage: on.epubTwoPage, scrollView: on.scrollView),
      600,
    );
    expect(
      epubTwoPageMinWidth(twoPage: off.epubTwoPage, scrollView: off.scrollView),
      isNull,
    );
    expect(
      epubTwoPageMinWidth(twoPage: on.epubTwoPage, scrollView: true),
      isNull,
      reason: 'scroll view has no pages',
    );
  });
}
