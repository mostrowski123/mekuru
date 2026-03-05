import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/database/database_provider.dart';
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
  static const _releasesApiUrl =
      'https://api.github.com/repos/yomidevs/jmdict-yomitan/releases/latest';

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
  /// - 0.0–0.05: resolving latest release tag
  /// - 0.05–0.70: downloading ZIP
  /// - 0.70–0.95: importing into database
  /// - 0.95–1.0: finalising
  static Future<void> downloadAndImport({
    required YomitanDictType type,
    required DictionaryRepository repository,
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // Phase 1: Resolve latest release tag
    final tag = await _fetchLatestTag();
    onProgress?.call(0.05);

    // Phase 2: Download ZIP
    final url =
        'https://github.com/yomidevs/jmdict-yomitan/releases/download/'
        '$tag/${_assetFilename(type)}';
    final zipBytes = await _downloadZip(
      url,
      onProgress: (p) => onProgress?.call(0.05 + p * 0.65),
    );

    // Phase 3: Write to temp file and import
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, '${type.name}_download.zip'));
    await tempFile.writeAsBytes(zipBytes);

    try {
      onProgress?.call(0.75);
      await importer.importFromFile(tempFile.path);
      onProgress?.call(0.95);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

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
    }
  }

  /// Fetch the latest release tag from the GitHub API.
  static Future<String> _fetchLatestTag() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_releasesApiUrl));
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      final response = await request.close();

      if (response.statusCode != 200) {
        // Drain the response to free resources
        await response.drain<void>();
        throw HttpException(
          'Failed to fetch latest release: HTTP ${response.statusCode}',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null || tag.isEmpty) {
        throw Exception('No tag_name found in GitHub release response');
      }
      return tag;
    } finally {
      client.close();
    }
  }

  /// Download a ZIP archive from [url], returning raw bytes.
  static Future<List<int>> _downloadZip(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      // Follow redirects manually if needed (GitHub releases redirect)
      if (response.statusCode == 301 || response.statusCode == 302) {
        final redirectUrl = response.headers.value('location');
        if (redirectUrl != null) {
          await response.drain<void>();
          final redirectRequest = await client.getUrl(Uri.parse(redirectUrl));
          final redirectResponse = await redirectRequest.close();
          return _readResponse(redirectResponse, onProgress: onProgress);
        }
      }

      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException(
          'Failed to download dictionary: HTTP ${response.statusCode}',
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
