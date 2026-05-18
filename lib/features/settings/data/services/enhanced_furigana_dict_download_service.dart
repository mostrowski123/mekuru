import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and installs the optional UniDic-lite MeCab dictionary.
///
/// UniDic-lite ships ~250 MB of dictionary data — too large to bundle in
/// the APK. When a user opts in via Settings, this service downloads the
/// tar.gz from a GitHub release, verifies its SHA-256, and extracts the
/// files into the app documents directory where MecabService can load
/// them on the next launch.
///
/// UniDic-lite is derived from the UniDic distribution by NINJAL and is
/// distributed under the BSD/CC/GPL/LGPL triple license (see the bundled
/// COPYING/BSD/GPL/LGPL files inside the archive).
class EnhancedFuriganaDictDownloadService {
  static const downloadUrl =
      'https://github.com/mostrowski123/mekuru/releases/download/'
      'dict-unidic-lite-v2.1.2/unidic-lite-2.1.2.tar.gz';

  /// SHA-256 of the published `unidic-lite-2.1.2.tar.gz`.
  ///
  /// Pinning the hash ensures the bytes we expand match exactly the
  /// dictionary the code was tested against. If the release artifact is
  /// ever re-uploaded, this constant must be updated.
  static const expectedSha256 =
      '3c4d23483dabe0c63218e7b95b5470290cfb122479c80401f32e2deafb411289';

  /// Approximate compressed download size in bytes (for UI progress hints).
  static const approxDownloadBytes = 45 * 1024 * 1024;

  /// Approximate on-disk size after extraction in bytes.
  static const approxInstalledBytes = 250 * 1024 * 1024;

  static const _localDirName = 'unidic-lite';
  static const _markerFileName = '.install_complete';

  /// Shared-preferences key matching
  /// [SharedPreferencesAppSettingsStorage._enhancedFuriganaDictEnabledKey].
  /// Read directly from MecabService (which has no DI surface for the
  /// settings storage interface) to decide which dictionary to load.
  static const enabledPreferenceKey = 'app.enhanced_furigana_dict_enabled';

  /// `true` if the user has opted in AND the dict files are installed.
  /// Used by MecabService to pick between IPADIC + user-dict (default)
  /// and the downloaded UniDic-lite layout.
  static Future<bool> shouldUse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(enabledPreferenceKey) ?? false;
      if (!enabled) return false;
      return isInstalled();
    } catch (e) {
      debugPrint('[EnhancedFurigana] shouldUse check failed: $e');
      return false;
    }
  }

  /// Absolute path to the directory where unidic-lite files live on disk.
  static Future<String> getStorageDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, _localDirName);
  }

  /// `true` if the unidic-lite archive has been fully downloaded, verified,
  /// and extracted.
  static Future<bool> isInstalled() async {
    final dir = await getStorageDir();
    return File(p.join(dir, _markerFileName)).existsSync();
  }

  /// Delete the installed unidic-lite files. Safe to call when the dict is
  /// not installed.
  static Future<void> uninstall() async {
    final dir = Directory(await getStorageDir());
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Download, verify, and extract unidic-lite. [onProgress] is called with
  /// a value in `[0, 1]`: roughly `0–0.85` covers the download, `0.85–1.0`
  /// covers the extraction.
  ///
  /// Throws an [HttpException] on network failures, a [FormatException]
  /// when the SHA-256 doesn't match, or an [Exception] on archive
  /// decoding failures.
  static Future<void> downloadAndInstall({
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    final dir = await getStorageDir();
    final outputDir = Directory(dir);
    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final bytes = await _downloadBytes(
      onProgress: (p) => onProgress?.call(p * 0.85),
    );

    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != expectedSha256) {
      await outputDir.delete(recursive: true);
      throw FormatException(
        'Downloaded unidic-lite hash mismatch: expected '
        '$expectedSha256, got $actualHash',
      );
    }

    onProgress?.call(0.85);

    await compute(
      _extractTarGz,
      _ExtractPayload(archiveBytes: bytes, outputDir: dir),
    );

    await File(p.join(dir, _markerFileName)).writeAsString(
      jsonEncode({
        'sha256': expectedSha256,
        'installed_at': DateTime.now().toIso8601String(),
      }),
    );

    onProgress?.call(1.0);
  }

  static Future<Uint8List> _downloadBytes({
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      var uri = Uri.parse(downloadUrl);
      HttpClientResponse response;
      for (var redirects = 0; redirects < 5; redirects++) {
        final request = await client.getUrl(uri);
        response = await request.close();
        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers.value('location');
          if (location == null) {
            throw HttpException('redirect without location from $uri');
          }
          uri = Uri.parse(location);
          await response.drain<void>();
          continue;
        }
        if (response.statusCode != 200) {
          throw HttpException(
            'failed to download enhanced furigana dict: HTTP '
            '${response.statusCode}',
          );
        }
        return _readResponse(response, onProgress: onProgress);
      }
      throw HttpException('too many redirects fetching $downloadUrl');
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> _readResponse(
    HttpClientResponse response, {
    void Function(double progress)? onProgress,
  }) async {
    final contentLength = response.contentLength;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response) {
      builder.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(received / contentLength);
      }
    }
    return builder.toBytes();
  }

  /// Runs on a background isolate via [compute].
  static void _extractTarGz(_ExtractPayload payload) {
    final decompressed = GZipDecoder().decodeBytes(payload.archiveBytes);
    final archive = TarDecoder().decodeBytes(decompressed);

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final relPath = entry.name;
      final fileName = p.basename(relPath);
      if (fileName.isEmpty || fileName.startsWith('.')) continue;
      final outputPath = p.join(payload.outputDir, fileName);
      final file = File(outputPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.content as List<int>);
    }
  }
}

class _ExtractPayload {
  final Uint8List archiveBytes;
  final String outputDir;

  const _ExtractPayload({required this.archiveBytes, required this.outputDir});
}
