import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';

/// Injectable boundary for user-initiated local OCR. Deliberately has no
/// entitlement or remote-server methods.
abstract interface class LocalOcrClient {
  Future<OcrModelState> modelState();
  Future<OcrJobProgress> start(OcrJobSpec spec);
  Future<bool> requestNotifications();
  Future<void> cancel(String jobId);
}

class NativeLocalOcrClient implements LocalOcrClient {
  const NativeLocalOcrClient({this.permissions = const FullBackupJobChannel()});

  /// The app's own permission bridge. MainActivity answers its request code
  /// before Flutter fans the result out to every plugin listener; going
  /// through a plugin instead crashed the app on the first scan, because
  /// ankidroid_for_flutter force-unwraps a pending result it never had on
  /// any foreign permission callback.
  final FullBackupJobApi permissions;

  @override
  Future<void> cancel(String jobId) => LocalMangaOcr.cancel(jobId);
  @override
  Future<OcrModelState> modelState() => LocalMangaOcr.modelState();
  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) => LocalMangaOcr.start(spec);
  @override
  Future<bool> requestNotifications() =>
      permissions.requestNotificationPermission();
}
