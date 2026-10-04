import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/services/background_work.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// iOS ended the background task a dictionary download ran in.
class DownloadStoppedException implements Exception {
  const DownloadStoppedException();

  @override
  String toString() => 'The download was stopped';
}

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
  ///
  /// On iOS it keeps running after the user leaves the app, as background
  /// work; when iOS ends that, it stops with [DownloadStoppedException] and
  /// imports nothing.
  static Future<void> downloadAndImportUrl({
    required String url,
    required String asset,
    required DictionaryImporter importer,
    int? requiredBytes,
    void Function(double progress)? onProgress,
    void Function(int dictionaryId)? onDictionaryCreated,
  }) async {
    final stopwatch = Stopwatch()..start();
    final workId = 'dictionary:$asset:${DateTime.now().microsecondsSinceEpoch}';
    var stopped = false;
    // A stop is noticed at the next progress report. The download and the
    // importer report from inside their loops, so throwing there ends the
    // download (its partial file is deleted) or rolls the import back.
    void report(double progress) {
      if (stopped) throw const DownloadStoppedException();
      BackgroundWork.instance.progress(workId, progress);
      onProgress?.call(progress);
    }

    try {
      if (requiredBytes != null) {
        final free = await _freeBytes();
        if (free != null && free < requiredBytes) {
          throw InsufficientSpaceException(neededBytes: requiredBytes - free);
        }
      }
      BackgroundWork.instance.start(
        workId,
        BackgroundJobKind.dictionary,
        onStopped: () => stopped = true,
      );
      report(0.0);
      final tempDir = await getTemporaryDirectory();
      // Unique, so two downloads at once never share a file.
      final fileName =
          'download_${DateTime.now().microsecondsSinceEpoch}_'
          '${p.basename(Uri.parse(url).path)}';
      await withDownloadedFile(
        url,
        p.join(tempDir.path, fileName),
        onProgress: (fraction) => report(fraction * downloadShare),
        use: (path) async {
          report(downloadShare);
          await importer.importFromFile(
            path,
            onDictionaryCreated: onDictionaryCreated,
            onProgress: (done, total) {
              if (total > 0) {
                report(downloadShare + (0.95 - downloadShare) * done / total);
              }
            },
          );
          // Saved: a stop now would only misreport a finished install.
          onProgress?.call(0.95);
        },
      );
      onProgress?.call(1.0);
      logUsage(
        'download.completed',
        attrs: {'asset': asset, 'duration_ms': stopwatch.elapsedMilliseconds},
      );
    } on DownloadStoppedException {
      logUsage('download.stopped', attrs: {'asset': asset});
      rethrow;
    } catch (error) {
      logFailure('download.failed', error, attrs: {'asset': asset});
      rethrow;
    } finally {
      BackgroundWork.instance.finish(workId);
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
