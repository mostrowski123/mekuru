import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart'
    show dictionaryRequiredMb;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/shared/downloads/download.dart';

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

  /// Free bytes its install needs ([dictionaryRequiredMb]): the zip and what
  /// its import added to a database, measured on 2026-11-21.
  static final requiredBytes = (dictionaryRequiredMb(6.0, 39.1) * 1e6).round();

  /// Check whether the JPDB frequency dictionary exists in the database.
  static Future<bool> isImported(DictionaryRepository repository) async {
    final meta = await repository.getDictionaryByName(dictionaryName);
    return meta != null;
  }

  /// Whether [dictionaries] (the dictionary list) hold it switched off, so
  /// it ranks nothing although it is installed.
  static bool isSwitchedOffIn(Iterable<DictionaryMeta> dictionaries) =>
      dictionaries.any((d) => d.name == dictionaryName && !d.isEnabled);

  /// Download the JPDB frequency dictionary and import it into the database,
  /// switched on and listed with the other dictionaries. It has no entries
  /// of its own: it ranks the other dictionaries' words while it is on.
  /// Does nothing when it is already imported, so a tap that beats a
  /// screen's status check can't add a second copy.
  ///
  /// [onProgress] reports [DictionaryDownloadService] progress.
  static Future<void> downloadAndImport({
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    required NetworkConsent network,
    void Function(double progress)? onProgress,
  }) async {
    if (await isImported(repository)) return;
    await DictionaryDownloadService.downloadAndImportUrl(
      kind: DownloadKind.fixedDictionary,
      url: downloadUrl,
      asset: 'jpdb_freq',
      importer: importer,
      network: network,
      requiredBytes: requiredBytes,
      onProgress: onProgress,
    );
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
