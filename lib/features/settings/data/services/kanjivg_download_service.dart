import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/ios_storage.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/core/utils/install_folder.dart';
import 'package:mekuru/core/utils/zip_decode.dart';
import 'package:mekuru/shared/downloads/download.dart';
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

  /// Download the KanjiVG archive from GitHub ([DownloadKind.kanjiVg]) and
  /// extract SVG files. [onProgress] gets 0.0–0.9 for the download, then
  /// 0.9–1.0 for the extraction. Throws on network errors, an invalid archive
  /// or disk write failures.
  static Future<int> downloadAndExtract({
    required NetworkConsent network,
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final count = await _downloadAndExtract(
        network: network,
        onProgress: onProgress,
      );
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
    required NetworkConsent network,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getStorageDir();
    // Before the room check: a half unpack takes room and is no install.
    await clearInstallLeftovers(dir, marker: _markerFileName);
    final count = await runDownload(
      const DownloadSpec(
        DownloadKind.kanjiVg,
        id: 'kanjivg',
        parts: [
          (
            name: 'kanjivg_download.zip',
            url: downloadUrl,
            bytes: null,
            sha256: null,
          ),
        ],
      ),
      network,
      share: 0.9,
      onProgress: onProgress,
      install: (zipPath, _) => fillInstallFolder(dir, (into) async {
        await excludeFromIosBackup([into]);
        // Extract SVGs (runs on isolate to avoid blocking UI)
        final count = await compute(extractSvgsFromArchive, (
          zipPath: zipPath,
          outputDir: into,
        ));
        // Write completion marker
        await File(p.join(into, _markerFileName)).writeAsString(
          'KanjiVG kanjivg-20220427\n'
          'Files: $count\n'
          'Downloaded: ${DateTime.now().toIso8601String()}\n',
        );
        return count;
      }),
    );
    await excludeFromIosBackup([dir]);
    return count;
  }

  /// Delete all downloaded KanjiVG files.
  static Future<void> delete() async {
    if (await deleteInstallFolder(await getStorageDir())) {
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
      final archive = decodeZip(input);
      var count = 0;

      for (final file in archive.files) {
        if (file.isFile && file.name.endsWith('.svg')) {
          // The archive contains paths like "kanjivg-kanjivg-20220427/kanji/04e00.svg"
          // We extract just the filename.
          final fileName = p.basename(file.name);
          final outputPath = p.join(payload.outputDir, fileName);
          File(outputPath).writeAsBytesSync(file.content as List<int>);
          // ArchiveFile caches what it inflates and never frees it, so without
          // this the isolate would hold all ~11k decompressed SVGs at once.
          // clear(), never close(): every entry shares the InputFileStream's
          // single file handle, and closing one would empty all the rest.
          file.clear();
          count++;
        }
      }

      // A zip, but not the stroke-order one: an empty install would look
      // downloaded.
      if (count == 0) {
        throw const FormatException('No stroke order files in the download');
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
