import 'dart:io';

/// Download [url] to [destinationPath], streaming the response body straight
/// to disk so large assets are never buffered in memory.
///
/// Redirects (GitHub release assets redirect to a CDN) are followed by
/// [HttpClient] itself, up to its default limit of 5 hops. [onProgress] is
/// called with values in `(0, 1]` when the server reports a content length,
/// at most once per whole percent so UI listeners aren't rebuilt for every
/// socket chunk.
///
/// No file is left behind on failure: a partially written download is
/// deleted before the error propagates. Throws an [HttpException] on non-200
/// responses; exceeding the redirect limit throws a [RedirectException],
/// which implements [HttpException].
Future<void> downloadToFile(
  String url,
  String destinationPath, {
  Map<String, String>? headers,
  void Function(double progress)? onProgress,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    headers?.forEach(request.headers.set);
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Download failed: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final contentLength = response.contentLength;
    var received = 0;
    var lastPercent = -1;
    final file = File(destinationPath);
    final raf = await file.open(mode: FileMode.write);
    var completed = false;
    try {
      // Awaiting each write pauses the socket subscription (await-for
      // applies backpressure), so slow storage can't balloon memory.
      await for (final chunk in response) {
        await raf.writeFrom(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final percent = received * 100 ~/ contentLength;
          if (percent > lastPercent) {
            lastPercent = percent;
            onProgress?.call(received / contentLength);
          }
        }
      }
      completed = true;
    } finally {
      await raf.close();
      if (!completed) {
        try {
          await file.delete();
        } on FileSystemException {
          // Best-effort cleanup; the original error is what matters.
        }
      }
    }
  } finally {
    client.close();
  }
}

/// Download [url] to [destinationPath], hand the path to [use], and delete
/// the file afterwards — also when the download or [use] throws.
///
/// Returns whatever [use] returns.
Future<T> withDownloadedFile<T>(
  String url,
  String destinationPath, {
  void Function(double progress)? onProgress,
  required Future<T> Function(String path) use,
}) async {
  try {
    await downloadToFile(url, destinationPath, onProgress: onProgress);
    return await use(destinationPath);
  } finally {
    try {
      await File(destinationPath).delete();
    } on FileSystemException {
      // Already gone (failed download) or undeletable; nothing to leak.
    }
  }
}
