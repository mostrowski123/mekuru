/// Server book downloads, the same Dart code on both platforms: an Android
/// WorkManager job runs [runServerDownloadWork], and iOS runs it in the app
/// (kept going in the background by `BackgroundWork`). It speaks http and
/// https, trusts a self-signed certificate the user accepted for that one
/// server, and continues a partial file after an interruption.
library;

import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:path/path.dart' as p;

/// WorkManager task name of a server book download (Android).
const serverDownloadTaskName = 'mekuru.server_download';

/// Tag on every such task, so a full restore can cancel them all.
const serverDownloadWorkTag = 'server_download';

/// Folder-name prefix of download folders under `server_downloads/`.
const serverDownloadJobDirPrefix = 'job_';

/// [ServerDownloadWorkStatus.error] of a download the user (or iOS) stopped.
const serverDownloadStoppedError = 'stopped';

/// [ServerDownloadWorkStatus.error] of a download whose server certificate
/// was rejected: a self-signed one, with the switch off.
const serverDownloadUntrustedCertificateError = 'untrusted_certificate';

/// Delete every download folder under [downloadsRoot]. A running download
/// notices its folder is gone and ends.
Future<void> deleteServerDownloadJobDirs(String downloadsRoot) async {
  final root = Directory(downloadsRoot);
  if (!await root.exists()) return;
  await for (final entity in root.list()) {
    if (entity is Directory &&
        p.basename(entity.path).startsWith(serverDownloadJobDirPrefix)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best effort; launch reports or removes what is left.
      }
    }
  }
}

/// WorkManager unique work name of the download keyed [key].
String serverDownloadWorkName(String key) => 'server_download_$key';

/// Consecutive failed attempts (no byte gained) before a download gives up.
/// Android stopping the worker (its ~10-minute window) is not an attempt:
/// the next run continues from the partial file.
const serverDownloadMaxFailedAttempts = 5;

enum ServerDownloadWorkState { running, done, failed }

/// What a worker download's folder says about it. The worker writes it; the
/// app reads it to show progress and to import the finished file.
class ServerDownloadWorkStatus {
  final ServerDownloadWorkState state;
  final int received;

  /// Total bytes, or -1 while unknown.
  final int total;
  final int failedAttempts;
  final String? error;

  const ServerDownloadWorkStatus({
    required this.state,
    this.received = 0,
    this.total = -1,
    this.failedAttempts = 0,
    this.error,
  });

  double? get progress => total > 0 ? received / total : null;

  /// This status, ended with [error].
  ServerDownloadWorkStatus failedWith(String error) => ServerDownloadWorkStatus(
    state: ServerDownloadWorkState.failed,
    received: received,
    total: total,
    failedAttempts: failedAttempts,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'received': received,
    'total': total,
    'failedAttempts': failedAttempts,
    'error': ?error,
  };

  static ServerDownloadWorkStatus? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final state = ServerDownloadWorkState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    if (state == null) return null;
    return ServerDownloadWorkStatus(
      state: state,
      received: json['received'] as int? ?? 0,
      total: json['total'] as int? ?? -1,
      failedAttempts: json['failedAttempts'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }
}

/// The folder of one worker download: `job.json` (written by the app: the
/// download key, file name and import metadata — never the credentials,
/// which travel in the WorkManager input), `status.json` (written by the
/// worker), and the file itself, as `<name>.part` until complete.
class ServerDownloadWorkDir {
  final String path;

  const ServerDownloadWorkDir(this.path);

  File get _jobFile => File(p.join(path, 'job.json'));
  File get _statusFile => File(p.join(path, 'status.json'));

  Future<void> writeJob({
    required String key,
    required String fileName,
    required Map<String, dynamic> meta,
  }) => writeStringAtomic(
    _jobFile,
    jsonEncode({'key': key, 'fileName': fileName, 'meta': meta}),
  );

  /// `(key, fileName, meta)`, or null when missing or unreadable.
  Future<({String key, String fileName, Map<String, dynamic> meta})?>
  readJob() async {
    try {
      final json = jsonDecode(await _jobFile.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return (
        key: json['key'] as String,
        fileName: json['fileName'] as String,
        meta: json['meta'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeStatus(ServerDownloadWorkStatus status) =>
      writeStringAtomic(_statusFile, jsonEncode(status.toJson()));

  Future<ServerDownloadWorkStatus?> readStatus() async {
    try {
      return ServerDownloadWorkStatus.fromJson(
        jsonDecode(await _statusFile.readAsString()),
      );
    } catch (_) {
      return null;
    }
  }

  String filePath(String fileName) => p.join(path, fileName);
}

/// WorkManager input of a worker download.
Map<String, dynamic> serverDownloadWorkInput({
  required String dir,
  required String fileName,
  required String url,
  required Map<String, String> headers,
  required String baseUrl,
  required bool allowSelfSigned,
}) => {
  'dir': dir,
  'fileName': fileName,
  'url': url,
  'headers': jsonEncode(headers),
  'baseUrl': baseUrl,
  'allowSelfSigned': allowSelfSigned,
};

/// Download, resuming any partial file, and record the outcome in the
/// folder's status. Returns true when the download is over (finished, failed
/// for good, or cancelled), false when it should be retried with backoff.
/// [client] is the caller's, so it can cancel by closing it.
Future<bool> runServerDownloadWork(
  Map<String, dynamic> input, {
  HttpClient? client,
}) async {
  final dir = ServerDownloadWorkDir(input['dir'] as String);
  // A full restore deletes the folder to cancel.
  if (!Directory(dir.path).existsSync()) return true;
  final fileName = input['fileName'] as String;
  final previous = await dir.readStatus();
  if (previous?.state == ServerDownloadWorkState.done) return true;
  final headers = (jsonDecode(input['headers'] as String) as Map)
      .cast<String, String>();
  client ??= serverIoClient(
    input['baseUrl'] as String,
    allowSelfSigned: input['allowSelfSigned'] as bool? ?? false,
  );
  final partPath = '${dir.filePath(fileName)}.part';
  final startBytes = await _lengthOrZero(partPath);
  var received = startBytes;
  var total = previous?.total ?? -1;
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  // Progress writes queue up here, so a late one can't land after (and
  // overwrite) the final status.
  var writes = Future<void>.value();
  try {
    await downloadResumable(
      input['url'] as String,
      partPath,
      client: client,
      headers: headers,
      onProgress: (bytes, size) {
        received = bytes;
        total = size;
        final now = DateTime.now();
        if (now.difference(lastWrite) < const Duration(milliseconds: 500)) {
          return;
        }
        lastWrite = now;
        final status = ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: bytes,
          total: size,
        );
        writes = writes.then((_) => dir.writeStatus(status)).catchError((_) {});
      },
    );
    await writes;
    await File(partPath).rename(dir.filePath(fileName));
    await dir.writeStatus(
      ServerDownloadWorkStatus(
        state: ServerDownloadWorkState.done,
        received: received,
        total: received,
      ),
    );
    return true;
  } catch (e) {
    await writes;
    if (!Directory(dir.path).existsSync()) return true;
    final gained = received > startBytes;
    final failedAttempts = gained ? 1 : (previous?.failedAttempts ?? 0) + 1;
    final untrusted = isUntrustedCertificateError(e);
    final permanent =
        untrusted || (e is ServerDownloadHttpException && e.isPermanent);
    final giveUp =
        permanent || failedAttempts >= serverDownloadMaxFailedAttempts;
    await dir.writeStatus(
      ServerDownloadWorkStatus(
        state: giveUp
            ? ServerDownloadWorkState.failed
            : ServerDownloadWorkState.running,
        received: received,
        total: total,
        failedAttempts: failedAttempts,
        error: untrusted ? serverDownloadUntrustedCertificateError : '$e',
      ),
    );
    return giveUp;
  } finally {
    client.close(force: true);
  }
}

Future<int> _lengthOrZero(String path) async {
  final file = File(path);
  return await file.exists() ? await file.length() : 0;
}

/// Non-2xx answer to a download request.
class ServerDownloadHttpException implements Exception {
  final int statusCode;

  const ServerDownloadHttpException(this.statusCode);

  /// Client errors won't fix themselves by retrying, except a timeout or
  /// rate limit.
  bool get isPermanent =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() => 'Download failed: HTTP $statusCode';
}

/// Download [url] into [partPath], continuing a partial file left by an
/// earlier attempt with a Range request. A server that ignores the range
/// (200) or answers a different one starts the file over. [onProgress] gets
/// the bytes on disk and the total (-1 when unknown).
Future<void> downloadResumable(
  String url,
  String partPath, {
  required HttpClient client,
  Map<String, String>? headers,
  void Function(int received, int total)? onProgress,
}) async {
  final part = File(partPath);
  var existing = await _lengthOrZero(partPath);
  final uri = Uri.parse(url);
  final request = await client.getUrl(uri);
  headers?.forEach(request.headers.set);
  if (existing > 0) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
  }
  final response = await request.close();

  final int total;
  final FileMode mode;
  if (existing > 0 &&
      response.statusCode == HttpStatus.partialContent &&
      (response.headers.value(HttpHeaders.contentRangeHeader) ?? '').startsWith(
        'bytes $existing-',
      )) {
    mode = FileMode.append;
    total = response.contentLength >= 0
        ? existing + response.contentLength
        : -1;
  } else if (response.statusCode == HttpStatus.ok) {
    existing = 0;
    mode = FileMode.write;
    total = response.contentLength;
  } else {
    await response.drain<void>();
    if (existing > 0 &&
        (response.statusCode == HttpStatus.partialContent ||
            response.statusCode == HttpStatus.requestedRangeNotSatisfiable)) {
      // The partial file no longer matches the server's: start over.
      await part.delete();
      return downloadResumable(
        url,
        partPath,
        client: client,
        headers: headers,
        onProgress: onProgress,
      );
    }
    throw ServerDownloadHttpException(response.statusCode);
  }

  final raf = await part.open(mode: mode);
  var received = existing;
  try {
    // Awaiting each write applies backpressure to the socket.
    await for (final chunk in response) {
      await raf.writeFrom(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
  } finally {
    await raf.close();
  }
  if (total >= 0 && received != total) {
    throw HttpException('Connection closed at $received of $total bytes');
  }
}

/// iOS downloads running in the app, by download key, so they can be
/// stopped: by the user or iOS ending the background task, or by a full
/// restore (`cancelServerDownloads`).
class InAppServerDownloads {
  InAppServerDownloads._();

  static final _clients = <String, HttpClient>{};
  static final _cancelled = <String>{};

  static void start(String key, HttpClient client) {
    _cancelled.remove(key);
    _clients[key] = client;
  }

  static void finish(String key) => _clients.remove(key);

  /// Whether [key] ended because it was cancelled.
  static bool wasCancelled(String key) => _cancelled.contains(key);

  /// Abort the download [key], if it is running.
  static void cancel(String key) {
    final client = _clients.remove(key);
    if (client == null) return;
    _cancelled.add(key);
    client.close(force: true);
  }

  /// Abort every running in-app download.
  static void cancelAll() => [..._clients.keys].forEach(cancel);
}
