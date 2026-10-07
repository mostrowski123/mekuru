import 'manga_ocr_client.dart';
import 'vision_page_ocr.dart';

/// Why an OCR run (or a custom OCR server's connection test) failed, as
/// `OcrProgress.errorMessage` keeps it: `ocr:`, the failure's name and, for
/// some, `:` and a detail. The app words it in the user's language
/// (`describeOcrFailure`); progress saved by an older version holds English
/// text, shown as it is. The names are stored: never rename one.
enum OcrFailure {
  certificateUntrusted,
  authFailed,
  jobForbidden,
  noCredits,
  jobNotFound,
  jobInactive,

  /// Detail: the server's explanation.
  rejected,

  /// Detail: the HTTP status.
  serverError,
  connectFailed,
  timedOut,
  hostNotFound,

  /// Detail: the system's error text.
  network,

  /// Detail: `<HTTP status>:<the server's explanation>`.
  status,
  malformedResponse,

  /// Detail: the error's own text.
  unexpected,
  serverUrlMissing,
  serverUrlInvalid,
  keyMissing,
  signInFailed,

  /// Detail: the image's path.
  pageImageMissing,

  /// Detail: the image's path inside the folder the user granted access to.
  pageImageAccessLost,
  recognitionFailed,

  /// A custom server's /health answered something other than "ok".
  /// Detail: what it answered.
  unhealthy;

  static const _prefix = 'ocr:';

  /// This failure as [OcrProgress.errorMessage] stores it.
  String code([Object? detail]) =>
      '$_prefix$name${detail == null ? '' : ':$detail'}';

  /// The failure and detail stored in [errorMessage], or null for text an
  /// older version stored.
  static ({OcrFailure failure, String detail})? parse(String errorMessage) {
    if (!errorMessage.startsWith(_prefix)) return null;
    final rest = errorMessage.substring(_prefix.length);
    final colon = rest.indexOf(':');
    final failure = values
        .asNameMap()[colon < 0 ? rest : rest.substring(0, colon)];
    if (failure == null) return null;
    return (
      failure: failure,
      detail: colon < 0 ? '' : rest.substring(colon + 1),
    );
  }
}

/// [error] as an [OcrFailure] code for `OcrProgress.errorMessage`.
String ocrErrorCode(Object error) {
  if ('$error'.contains('CERTIFICATE_VERIFY_FAILED')) {
    return OcrFailure.certificateUntrusted.code();
  }
  if (error is TextRecognitionException) {
    return OcrFailure.recognitionFailed.code();
  }
  if (error is OcrServerException) {
    return switch (error.statusCode) {
      401 => OcrFailure.authFailed.code(),
      // job_forbidden: the OCR job belongs to a different account.
      403 when error.code == 'job_forbidden' => OcrFailure.jobForbidden.code(),
      403 => OcrFailure.authFailed.code(),
      402 => OcrFailure.noCredits.code(),
      404 => OcrFailure.jobNotFound.code(),
      // job_expired or job_not_active
      409 => OcrFailure.jobInactive.code(),
      422 => OcrFailure.rejected.code(error.message),
      >= 500 => OcrFailure.serverError.code(error.statusCode),
      // Network-level errors from the client
      0 => ocrNetworkErrorCode(error.message),
      _ => OcrFailure.status.code('${error.statusCode}:${error.message}'),
    };
  }
  final desc = error.toString().toLowerCase();
  if (desc.contains('formatexception') || desc.contains('type \'')) {
    return OcrFailure.malformedResponse.code();
  }
  return OcrFailure.unexpected.code(error);
}

/// A failed connection to an OCR server as an [OcrFailure] code, from the
/// system's [message].
String ocrNetworkErrorCode(String message) {
  final msg = message.toLowerCase();
  if (msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('no route to host')) {
    return OcrFailure.connectFailed.code();
  }
  if (msg.contains('timed out')) return OcrFailure.timedOut.code();
  if (msg.contains('no address associated') ||
      msg.contains('name or service not known') ||
      msg.contains('getaddrinfo') ||
      msg.contains('failed host lookup')) {
    return OcrFailure.hostNotFound.code();
  }
  // The OCR client's message already says "Network error: ".
  return OcrFailure.network.code(message.replaceFirst('Network error: ', ''));
}
