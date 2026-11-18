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

  test('two pages show only when switched on, paginated and wide enough', () {
    const on = ReaderSettings(epubTwoPage: true);
    // Tablets, unfolded foldables and phones held sideways.
    expect(epubShowsTwoPages(on, pageWidth: 600), isTrue);
    expect(epubShowsTwoPages(on, pageWidth: 1180), isTrue);
    // A phone held upright, a folded foldable's cover screen.
    expect(epubShowsTwoPages(on, pageWidth: 599), isFalse);
    expect(epubShowsTwoPages(const ReaderSettings(), pageWidth: 1180), isFalse);
    expect(
      epubShowsTwoPages(on.copyWith(scrollView: true), pageWidth: 1180),
      isFalse,
      reason: 'scroll view has no pages',
    );
  });
}
