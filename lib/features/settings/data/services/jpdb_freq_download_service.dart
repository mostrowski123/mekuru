import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for downloading and managing the JPDB frequency dictionary.
///
/// Unlike KanjiVG (which stores files on disk), this service downloads a
/// Yomitan-format ZIP and imports it into the database via [DictionaryImporter].
///
/// Data source: https://jpdb.io
/// Distribution: https://github.com/Kuuuube/yomitan-dictionaries
class JpdbFreqDownloadService {
  /// GitHub raw URL for the JPDB frequency dictionary ZIP.
  static const downloadUrl =
      'https://github.com/Kuuuube/yomitan-dictionaries/raw/main/'
      'dictionaries/JPDB_v2.2_Frequency_Kana_2024-10-13.zip';

  /// The dictionary name as stored in the database after import.
  static const dictionaryName = 'JPDBv2\u32D5';

  /// Check whether the JPDB frequency dictionary exists in the database.
  static Future<bool> isImported(DictionaryRepository repository) async {
    final meta = await repository.getDictionaryByName(dictionaryName);
    return meta != null;
  }

  /// Download the JPDB frequency dictionary and import it into the database.
  ///
  /// [onProgress] is called with a value between 0.0 and 1.0.
  /// - 0.0–0.7: download phase
  /// - 0.7–0.95: import phase
  /// - 0.95–1.0: finalising
  static Future<void> downloadAndImport({
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _downloadAndImport(
        repository: repository,
        importer: importer,
        onProgress: onProgress,
      );
      logUsage(
        'download.completed',
        attrs: {
          'asset': 'jpdb_freq',
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error) {
      logFailure('download.failed', error, attrs: {'asset': 'jpdb_freq'});
      rethrow;
    }
  }

  static Future<void> _downloadAndImport({
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    final tempDir = await getTemporaryDirectory();
    await withDownloadedFile(
      downloadUrl,
      p.join(tempDir.path, 'jpdb_freq_download.zip'),
      onProgress: (p) => onProgress?.call(p * 0.7),
      use: (path) async {
        // Import via standard importer
        onProgress?.call(0.8);
        await importer.importFromFile(path);

        // Mark as hidden and disabled
        onProgress?.call(0.95);
        final meta = await repository.getDictionaryByName(dictionaryName);
        if (meta != null) {
          await repository.toggleDictionary(meta.id, isEnabled: false);
          await repository.setHidden(meta.id, isHidden: true);
        }
      },
    );

    onProgress?.call(1.0);
  }

  /// Delete the JPDB frequency dictionary and all its data from the database.
  static Future<void> delete(DictionaryRepository repository) async {
    final meta = await repository.getDictionaryByName(dictionaryName);
    if (meta != null) {
      await repository.deleteDictionary(meta.id);
      logUsage('download.uninstalled', attrs: {'asset': 'jpdb_freq'});
    }
  }
}
