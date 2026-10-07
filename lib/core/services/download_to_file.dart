import 'dart:async';
import 'dart:io';

import 'package:mekuru/core/platform/network_status.dart';

/// A non-200 answer to [downloadToFile].
class DownloadHttpException extends HttpException {
  final int statusCode;

  const DownloadHttpException(this.statusCode, {super.uri})
    : super('Download failed: HTTP $statusCode');
}

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
/// which implements [HttpException]. Throws a [TimeoutException] when
/// nothing arrives for [stallTimeout] (tests shorten it) while connecting,
/// waiting for the response or mid-body: a stalled connection would
/// otherwise hang the download forever, while a slow one still finishes.
///
/// [headers] are sent with the request. [client] replaces the default
/// [HttpClient] (e.g. one that accepts a server's self-signed certificate);
/// it is closed when the download ends, and closing it with `force: true`
/// meanwhile cancels the download.
Future<void> downloadToFile(
  String url,
  String destinationPath, {
  void Function(double progress)? onProgress,
  Map<String, String>? headers,
  HttpClient? client,
  Duration stallTimeout = const Duration(seconds: 30),
}) async {
  client ??= HttpClient();
  client.connectionTimeout ??= stallTimeout;
  var completed = false;
  try {
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    headers?.forEach(request.headers.set);
    final response = await request.close().timeout(stallTimeout);

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw DownloadHttpException(response.statusCode, uri: uri);
    }

    final contentLength = response.contentLength;
    var received = 0;
    var lastPercent = -1;
    final file = File(destinationPath);
    final raf = await file.open(mode: FileMode.write);
    try {
      // Awaiting each write pauses the socket subscription (await-for
      // applies backpressure), so slow storage can't balloon memory.
      await for (final chunk in response.timeout(stallTimeout)) {
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
    // Forced on failure: a stalled connection would otherwise linger.
    client.close(force: !completed);
  }
}

/// Download [url] to [destinationPath], hand the path to [use], and delete
/// the file afterwards — also when the download or [use] throws.
///
/// With [wifiOnly], the download stops with [WifiLostException] once the
/// network is no longer Wi-Fi ([whileOnWifi]); [use] is not watched.
///
/// Returns whatever [use] returns.
Future<T> withDownloadedFile<T>(
  String url,
  String destinationPath, {
  void Function(double progress)? onProgress,
  bool wifiOnly = false,
  required Future<T> Function(String path) use,
}) async {
  try {
    final client = HttpClient();
    Future<void> download() => downloadToFile(
      url,
      destinationPath,
      onProgress: onProgress,
      client: client,
    );
    await (wifiOnly ? whileOnWifi(client, download) : download());
    return await use(destinationPath);
  } finally {
    try {
      await File(destinationPath).delete();
    } on FileSystemException {
      // Already gone (failed download) or undeletable; nothing to leak.
    }
  }
}
