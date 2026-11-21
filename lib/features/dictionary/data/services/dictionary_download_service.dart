import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:path/path.dart' as p;

/// Downloads Yomitan dictionary zips and imports them.
class DictionaryDownloadService {
  /// The part of the progress spent downloading; importing takes the rest.
  static const downloadShare = 0.7;

  /// Where the progress waits while the import finishes, which for a big
  /// dictionary takes a while without reports.
  static const finishingProgress = 0.95;

  /// Downloads [url] as a download of [kind] and imports it.
  ///
  /// [onProgress] gets 0–[downloadShare] while downloading, then up to
  /// [finishingProgress] while importing, stays there while the import
  /// finishes, and gets 1.0 when done. [asset] names the download in
  /// telemetry. [requiredBytes] is the room the import needs, when [kind]
  /// checks for room. A stop ([DownloadStoppedException]) imports nothing.
  static Future<void> downloadAndImportUrl({
    required DownloadKind kind,
    required String url,
    required String asset,
    required DictionaryImporter importer,
    required NetworkConsent network,
    int? requiredBytes,
    void Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await runDownload<void>(
        DownloadSpec(
          kind,
          id: 'dictionary:$asset:${DateTime.now().microsecondsSinceEpoch}',
          parts: [
            (
              name: p.basename(Uri.parse(url).path),
              url: url,
              bytes: null,
              sha256: null,
            ),
          ],
          extraBytes: requiredBytes ?? 0,
        ),
        network,
        share: downloadShare,
        onProgress: onProgress,
        install: (path, report) async {
          await importer.importFromFile(
            path,
            onProgress: (done, total) {
              if (total > 0) {
                report(
                  downloadShare +
                      (finishingProgress - downloadShare) * done / total,
                );
              }
            },
            onFinishing: () => report(finishingProgress),
          );
        },
      );
      logUsage(
        'download.completed',
        attrs: {'asset': asset, 'duration_ms': stopwatch.elapsedMilliseconds},
      );
    } on DownloadStoppedException {
      logUsage('download.stopped', attrs: {'asset': asset});
      rethrow;
    } on WifiLostException {
      logUsage('download.wifi_lost', attrs: {'asset': asset});
      rethrow;
    } on DownloadStoppedInBackgroundException catch (e) {
      // What failed under the blocked network: a full disk, say. On the
      // user's side, so a log rather than an issue.
      logUsage(
        'download.stopped_in_background',
        attrs: {
          'asset': asset,
          'user_side': true,
          if (e.cause case final cause?) ...{
            'error_type': cause.runtimeType.toString(),
            'error_message': sanitizeErrorText('$cause'),
          },
        },
      );
      rethrow;
    } catch (error) {
      logFailure('download.failed', error, attrs: {'asset': asset});
      rethrow;
    }
  }
}
