import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads Yomitan dictionary zips and imports them.
class DictionaryDownloadService {
  /// The part of the progress spent downloading; importing takes the rest.
  static const downloadShare = 0.7;

  /// Downloads [url] to a temporary file and imports it.
  ///
  /// [onProgress] gets 0–[downloadShare] while downloading, then up to 0.95
  /// while importing and 1.0 when done. [asset] names the download in
  /// telemetry. With [requiredBytes], throws [InsufficientSpaceException]
  /// before downloading when less is free.
  static Future<void> downloadAndImportUrl({
    required String url,
    required String asset,
    required DictionaryImporter importer,
    int? requiredBytes,
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (requiredBytes != null) {
        final free = await _freeBytes();
        if (free != null && free < requiredBytes) {
          throw InsufficientSpaceException(neededBytes: requiredBytes - free);
        }
      }
      onProgress?.call(0.0);
      final tempDir = await getTemporaryDirectory();
      // Named after the URL, so two downloads at once never share a file.
      final fileName = 'download_${p.basename(Uri.parse(url).path)}';
      await withDownloadedFile(
        url,
        p.join(tempDir.path, fileName),
        onProgress: (fraction) => onProgress?.call(fraction * downloadShare),
        use: (path) async {
          onProgress?.call(downloadShare);
          await importer.importFromFile(
            path,
            onProgress: (done, total) {
              if (total > 0) {
                onProgress?.call(
                  downloadShare + (0.95 - downloadShare) * done / total,
                );
              }
            },
          );
          onProgress?.call(0.95);
        },
      );
      onProgress?.call(1.0);
      logUsage(
        'download.completed',
        attrs: {'asset': asset, 'duration_ms': stopwatch.elapsedMilliseconds},
      );
    } catch (error) {
      logFailure('download.failed', error, attrs: {'asset': asset});
      rethrow;
    }
  }

  /// Free bytes where the database grows; null when unknown, and then the
  /// import fails loudly instead.
  static Future<int?> _freeBytes() async {
    try {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? await IosFullBackup.freeBytes()
          : await AndroidSafService.getFreeBytes(
              (await getApplicationSupportDirectory()).path,
            );
    } catch (_) {
      return null;
    }
  }
}
