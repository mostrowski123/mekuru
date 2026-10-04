import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';

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
  /// Does nothing when it is already imported, so a tap that beats a
  /// screen's status check can't add a second copy.
  ///
  /// [onProgress] reports [DictionaryDownloadService] progress.
  static Future<void> downloadAndImport({
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    if (await isImported(repository)) return;
    await DictionaryDownloadService.downloadAndImportUrl(
      url: downloadUrl,
      asset: 'jpdb_freq',
      importer: importer,
      onProgress: onProgress,
    );
    // Ranking data, not a dictionary to look words up in.
    final meta = await repository.getDictionaryByName(dictionaryName);
    if (meta != null) {
      await repository.toggleDictionary(meta.id, isEnabled: false);
      await repository.setHidden(meta.id, isHidden: true);
    }
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
