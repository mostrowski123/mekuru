import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

void main() {
  group('YomitanDictDownloadService.assetUrl', () {
    test('points at releases/latest/download so no GitHub API call is needed', () {
      // The api.github.com "latest release" endpoint is rate-limited to 60
      // unauthenticated requests per hour per IP, which real users hit (CGNAT
      // IPs shared by many devices). The latest/download form is served by
      // github.com directly and is not subject to the API rate limit.
      expect(
        YomitanDictDownloadService.assetUrl(YomitanDictType.jmdictEnglish),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english.zip',
      );
      expect(
        YomitanDictDownloadService.assetUrl(
          YomitanDictType.jmdictEnglishWithExamples,
        ),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english_with_examples.zip',
      );
      expect(
        YomitanDictDownloadService.assetUrl(YomitanDictType.kanjidicEnglish),
        'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/KANJIDIC_english.zip',
      );
    });
  });
}
