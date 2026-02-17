import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for downloading and managing KanjiVG SVG stroke order files.
///
/// KanjiVG files are downloaded as a ZIP archive from GitHub releases,
/// extracted to the app's documents directory, and stored for offline use.
///
/// KanjiVG is copyright Ulrich Apel and licensed under
/// Creative Commons Attribution-Share Alike 3.0 (CC BY-SA 3.0).
/// See https://kanjivg.tagaini.net/ and https://github.com/KanjiVG/kanjivg
class KanjiVgDownloadService {
  /// GitHub release archive URL for KanjiVG SVGs.
  static const downloadUrl =
      'https://github.com/KanjiVG/kanjivg/releases/download/'
      'r20250816/kanjivg-20250816-all.zip';

  /// Local directory name where SVGs are stored.
  static const _localDirName = 'kanjivg';

  /// Marker file written after a successful download + extraction.
  static const _markerFileName = '.kanjivg_complete';

  /// Returns the absolute path to the local KanjiVG storage directory.
  static Future<String> getStorageDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, _localDirName);
  }

  /// Returns `true` if KanjiVG SVGs have been fully downloaded and extracted.
  static Future<bool> isDownloaded() async {
    final dir = await getStorageDir();
    final marker = File(p.join(dir, _markerFileName));
    return marker.existsSync();
  }

  /// Returns the number of SVG files currently stored locally.
  static Future<int> fileCount() async {
    final dir = Directory(await getStorageDir());
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity.path.endsWith('.svg')) count++;
    }
    return count;
  }

  /// Returns the absolute path to the SVG file for [kanji], or `null` if
  /// not downloaded. The filename is the Unicode code point in lowercase hex
  /// (e.g. `04e00.svg` for 一).
  static Future<String?> getSvgPath(String kanji) async {
    if (kanji.isEmpty) return null;
    final codePoint = kanji.codeUnitAt(0);
    final hex = codePoint.toRadixString(16).padLeft(5, '0');
    final dir = await getStorageDir();
    final path = p.join(dir, '$hex.svg');
    if (File(path).existsSync()) return path;
    return null;
  }

  /// Download the KanjiVG archive from GitHub and extract SVG files.
  ///
  /// [onProgress] is called with a value between 0.0 and 1.0 during download.
  /// The extraction phase reports progress as 0.9–1.0.
  ///
  /// Throws on network errors, invalid archive, or disk write failures.
  static Future<int> downloadAndExtract({
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getStorageDir();
    final outputDir = Directory(dir);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Phase 1: Download ZIP
    onProgress?.call(0.0);
    final zipBytes = await _downloadZip(
      onProgress: (p) => onProgress?.call(p * 0.9), // 0–90% for download
    );

    // Phase 2: Extract SVGs (runs on isolate to avoid blocking UI)
    onProgress?.call(0.9);
    final count = await compute(
      _extractSvgsFromArchive,
      _ExtractPayload(zipBytes: zipBytes, outputDir: dir),
    );

    // Write completion marker
    await File(p.join(dir, _markerFileName)).writeAsString(
      'KanjiVG kanjivg-20220427\n'
      'Files: $count\n'
      'Downloaded: ${DateTime.now().toIso8601String()}\n',
    );

    onProgress?.call(1.0);
    return count;
  }

  /// Delete all downloaded KanjiVG files.
  static Future<void> delete() async {
    final dir = Directory(await getStorageDir());
    if (await dir.exists()) {
      await dir.delete(recursive: true);
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
          'Failed to download KanjiVG: HTTP ${response.statusCode}',
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

  /// Extract SVG files from the KanjiVG ZIP archive.
  /// Runs on an isolate via [compute].
  static int _extractSvgsFromArchive(_ExtractPayload payload) {
    final archive = ZipDecoder().decodeBytes(payload.zipBytes);
    var count = 0;

    for (final file in archive) {
      if (file.isFile && file.name.endsWith('.svg')) {
        // The archive contains paths like "kanjivg-kanjivg-20220427/kanji/04e00.svg"
        // We extract just the filename.
        final fileName = p.basename(file.name);
        final outputPath = p.join(payload.outputDir, fileName);
        File(outputPath).writeAsBytesSync(file.content as List<int>);
        count++;
      }
    }

    return count;
  }
}

/// Payload for the isolate extraction function.
class _ExtractPayload {
  final List<int> zipBytes;
  final String outputDir;

  const _ExtractPayload({required this.zipBytes, required this.outputDir});
}
