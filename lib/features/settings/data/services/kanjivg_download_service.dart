import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
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
    final stopwatch = Stopwatch()..start();
    try {
      final count = await _downloadAndExtract(onProgress: onProgress);
      logUsage(
        'download.completed',
        attrs: {
          'asset': 'kanjivg',
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return count;
    } catch (error) {
      logFailure('download.failed', error, attrs: {'asset': 'kanjivg'});
      rethrow;
    }
  }

  static Future<int> _downloadAndExtract({
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getStorageDir();
    final outputDir = Directory(dir);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Phase 1: Download ZIP straight to disk
    onProgress?.call(0.0);
    final tempDir = await getTemporaryDirectory();
    final count = await withDownloadedFile(
      downloadUrl,
      p.join(tempDir.path, 'kanjivg_download.zip'),
      onProgress: (p) => onProgress?.call(p * 0.9), // 0–90% for download
      use: (zipPath) {
        // Phase 2: Extract SVGs (runs on isolate to avoid blocking UI)
        onProgress?.call(0.9);
        return compute(extractSvgsFromArchive, (
          zipPath: zipPath,
          outputDir: dir,
        ));
      },
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
      logUsage('download.uninstalled', attrs: {'asset': 'kanjivg'});
    }
  }

  /// Extract SVG files from the KanjiVG ZIP archive.
  /// Runs on an isolate via [compute]; stream-decodes the ZIP from disk so
  /// the archive is never fully buffered in memory.
  @visibleForTesting
  static int extractSvgsFromArchive(
    ({String zipPath, String outputDir}) payload,
  ) {
    final input = InputFileStream(payload.zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      var count = 0;

      for (final file in archive.files) {
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
    } finally {
      // closeSync, not close(): close() returns a Future this sync isolate
      // entry point can't await, so the OS handle would be released at GC
      // timing — on Windows that races any deleteSync of the zip's parent
      // directory into a sharing violation.
      input.closeSync();
    }
  }
}
