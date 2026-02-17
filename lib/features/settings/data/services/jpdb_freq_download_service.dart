import 'dart:io';

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
    onProgress?.call(0.0);

    // Phase 1: Download ZIP
    final zipBytes = await _downloadZip(
      onProgress: (p) => onProgress?.call(p * 0.7),
    );

    // Phase 2: Write to temp file
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'jpdb_freq_download.zip'));
    await tempFile.writeAsBytes(zipBytes);

    try {
      // Phase 3: Import via standard importer
      onProgress?.call(0.8);
      await importer.importFromFile(tempFile.path);

      // Phase 4: Mark as hidden and disabled
      onProgress?.call(0.95);
      final meta = await repository.getDictionaryByName(dictionaryName);
      if (meta != null) {
        await repository.toggleDictionary(meta.id, isEnabled: false);
        await repository.setHidden(meta.id, isHidden: true);
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

    onProgress?.call(1.0);
  }

  /// Delete the JPDB frequency dictionary and all its data from the database.
  static Future<void> delete(DictionaryRepository repository) async {
    final meta = await repository.getDictionaryByName(dictionaryName);
    if (meta != null) {
      await repository.deleteDictionary(meta.id);
    }
  }

  /// Download the ZIP archive, returning raw bytes.
  static Future<List<int>> _downloadZip({
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      final response = await request.close();

      // Follow redirects manually if needed
      if (response.statusCode == 301 || response.statusCode == 302) {
        final redirectUrl = response.headers.value('location');
        if (redirectUrl != null) {
          final redirectRequest = await client.getUrl(Uri.parse(redirectUrl));
          final redirectResponse = await redirectRequest.close();
          return _readResponse(redirectResponse, onProgress: onProgress);
        }
      }

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download JPDB frequency dictionary: HTTP ${response.statusCode}',
        );
      }

      return _readResponse(response, onProgress: onProgress);
    } finally {
      client.close();
    }
  }

  static Future<List<int>> _readResponse(
    HttpClientResponse response, {
    void Function(double progress)? onProgress,
  }) async {
    final contentLength = response.contentLength;
    final bytes = <int>[];
    var received = 0;

    await for (final chunk in response) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(received / contentLength);
      }
    }

    return bytes;
  }
}
