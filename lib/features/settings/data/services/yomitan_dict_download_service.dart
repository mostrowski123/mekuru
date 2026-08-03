import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
      '${_assetFilename(type)}';

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
    final prefix = _namePrefix(type);
    final all = await repository.getAllDictionaries();
    return all.any((d) => d.name.startsWith(prefix));
  }

  /// Find the first imported dictionary matching this type's name prefix.
  static Future<DictionaryMeta?> _findImported(
    YomitanDictType type,
    DictionaryRepository repository,
  ) async {
    final prefix = _namePrefix(type);
    final all = await repository.getAllDictionaries();
    for (final d in all) {
      if (d.name.startsWith(prefix)) return d;
    }
    return null;
  }

  /// Fetch the latest release, download the ZIP, and import it.
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
    final stopwatch = Stopwatch()..start();
    try {
      await _downloadAndImport(
        type: type,
        importer: importer,
        onProgress: onProgress,
      );
      logUsage(
        'download.completed',
        attrs: {
          'asset': 'yomitan_collection',
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error) {
      logFailure(
        'download.failed',
        error,
        attrs: {'asset': 'yomitan_collection'},
      );
      rethrow;
    }
  }

  static Future<void> _downloadAndImport({
    required YomitanDictType type,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // Download the ZIP straight to disk to avoid buffering large
    // dictionaries in memory.
    final tempDir = await getTemporaryDirectory();
    await withDownloadedFile(
      assetUrl(type),
      p.join(tempDir.path, '${type.name}_download.zip'),
      onProgress: (p) => onProgress?.call(p * 0.7),
      use: (path) async {
        onProgress?.call(0.75);
        await importer.importFromFile(path);
        onProgress?.call(0.95);
      },
    );

    onProgress?.call(1.0);
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
