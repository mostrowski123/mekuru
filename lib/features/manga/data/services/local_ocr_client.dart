import 'package:local_manga_ocr/local_manga_ocr.dart';

/// Injectable boundary for user-initiated local OCR. Deliberately has no
/// entitlement or remote-server methods.
abstract interface class LocalOcrClient {
  Future<OcrModelState> modelState();
  Future<OcrJobProgress> start(OcrJobSpec spec);
  Future<bool> requestNotifications();
  Future<void> cancel(String jobId);
}

class NativeLocalOcrClient implements LocalOcrClient {
  const NativeLocalOcrClient();
  @override
  Future<void> cancel(String jobId) => LocalMangaOcr.cancel(jobId);
  @override
  Future<OcrModelState> modelState() => LocalMangaOcr.modelState();
  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) => LocalMangaOcr.start(spec);
  @override
  Future<bool> requestNotifications() => LocalMangaOcr.requestNotifications();
}
