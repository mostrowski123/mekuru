import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart'
    show jmdictYomitanReleases;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';

/// Dictionary types available for one-tap download from GitHub releases.
enum YomitanDictType {
  jmdictEnglish,
  jmdictEnglishWithExamples,
  kanjidicEnglish,
}

/// Service for downloading JMdict and KANJIDIC dictionaries from the
/// yomidevs/jmdict-yomitan GitHub releases.
///
/// Data source: Electronic Dictionary Research and Development Group (EDRDG).
/// JMdict and KANJIDIC are licensed under CC BY-SA 4.0.
/// Distribution: https://github.com/yomidevs/jmdict-yomitan
class YomitanDictDownloadService {
  /// URL of a release asset, via the `releases/latest/download` redirect.
  ///
  /// Deliberately not the GitHub API: `api.github.com` allows only 60
  /// unauthenticated requests per hour per IP, which users on shared (CGNAT)
  /// IPs exhaust, while this form has no API rate limit.
  static String assetUrl(YomitanDictType type) =>
      '$jmdictYomitanReleases/${_assetFilename(type)}';

  /// Name prefixes used to detect whether a dictionary type is already
  /// imported. The actual title comes from the ZIP's index.json and may vary
  /// between releases, so we match by prefix for robustness.
  static const _jmdictPrefix = 'JMdict';
  static const _kanjidicPrefix = 'KANJIDIC';

  /// Asset filename in the GitHub release for each type.
  static String _assetFilename(YomitanDictType type) => switch (type) {
    YomitanDictType.jmdictEnglish => 'JMdict_english.zip',
    YomitanDictType.jmdictEnglishWithExamples =>
      'JMdict_english_with_examples.zip',
    YomitanDictType.kanjidicEnglish => 'KANJIDIC_english.zip',
  };

  /// The name prefix used to detect whether this type is already imported.
  static String _namePrefix(YomitanDictType type) => switch (type) {
    YomitanDictType.jmdictEnglish ||
    YomitanDictType.jmdictEnglishWithExamples => _jmdictPrefix,
    YomitanDictType.kanjidicEnglish => _kanjidicPrefix,
  };

  /// Check whether a dictionary of this type is already imported.
  ///
  /// Uses prefix matching because the exact title in the ZIP's index.json
  /// may vary between releases (e.g. "JMdict (English)" vs "JMdict").
  static Future<bool> isImported(
    YomitanDictType type,
    DictionaryRepository repository,
  ) async {
    final all = await repository.getAllDictionaries();
    return all.any((d) => _matches(type, d.name));
  }

  /// Find the first imported dictionary matching this type's name prefix.
  static Future<DictionaryMeta?> _findImported(
    YomitanDictType type,
    DictionaryRepository repository,
  ) async {
    final all = await repository.getAllDictionaries();
    for (final d in all) {
      if (_matches(type, d.name)) return d;
    }
    return null;
  }

  /// A parenthesized language other than English marks another edition
  /// ("JMdict (Spanish) [..]", "KANJIDIC (French) [..]"), which is a separate
  /// download and must not count as, or be deleted as, the English one.
  static final _otherLanguageEdition = RegExp(
    r'^(JMdict|KANJIDIC) \((?!English)',
  );

  static bool _matches(YomitanDictType type, String name) =>
      name.startsWith(_namePrefix(type)) &&
      !_otherLanguageEdition.hasMatch(name);

  /// Fetch the latest release, download the ZIP, and import it. Does
  /// nothing when this type is already imported, so a tap that beats a
  /// screen's status check can't add a second copy.
  ///
  /// [onProgress] is called with a value between 0.0 and 1.0:
  /// - 0.0–0.70: downloading ZIP
  /// - 0.70–0.95: importing into database
  /// - 0.95–1.0: finalising
  static Future<void> downloadAndImport({
    required YomitanDictType type,
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    if (await isImported(type, repository)) return;
    await DictionaryDownloadService.downloadAndImportUrl(
      url: assetUrl(type),
      asset: 'yomitan_collection',
      importer: importer,
      onProgress: onProgress,
    );
  }

  /// Delete a dictionary by its name prefix.
  static Future<void> delete(
    YomitanDictType type,
    DictionaryRepository repository,
  ) async {
    final meta = await _findImported(type, repository);
    if (meta != null) {
      await repository.deleteDictionary(meta.id);
      logUsage('download.uninstalled', attrs: {'asset': 'yomitan_collection'});
    }
  }
}
