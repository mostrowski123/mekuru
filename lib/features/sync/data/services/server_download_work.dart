/// Server book downloads, the same Dart code on both platforms: an Android
/// WorkManager job runs [runServerDownloadWork], and iOS runs it in the app
/// (kept going in the background by `BackgroundWork`). It speaks http and
/// https, trusts a self-signed certificate the user accepted for that one
/// server, and continues a partial file after an interruption.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/core/utils/storage_full.dart';
import 'package:path/path.dart' as p;

import 'server_client.dart';

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

/// [ServerDownloadWorkStatus.error] of an Android download whose WorkManager
/// job was dropped (the app force-stopped or updated) before it finished.
const serverDownloadInterruptedError = 'interrupted';

/// [ServerDownloadWorkStatus.error] of an iOS download that could not be
/// restarted because its server connection was deleted or turned off.
const serverDownloadConnectionGoneError = 'connection_gone';

/// [ServerDownloadWorkStatus.error] of a download that filled the disk. A
/// server book's partial file is deleted, so the space it took is free
/// again; a pinned-size download keeps all but a tail of its, to resume.
const serverDownloadStorageFullError = 'storage_full';

/// Prefix of the [ServerDownloadWorkStatus.error] of a download the server
/// answered with an error status, e.g. `server_status:401`, or never
/// answered (`server_status:0`). The app explains it in the user's language.
const serverDownloadStatusErrorPrefix = 'server_status:';

/// The HTTP status in a [ServerDownloadWorkStatus.error] code (0: the server
/// could not be reached), or null for any other error.
int? serverDownloadErrorStatus(String error) =>
    error.startsWith(serverDownloadStatusErrorPrefix)
    ? int.tryParse(error.substring(serverDownloadStatusErrorPrefix.length))
    : null;

/// A download that a worker recorded as failed, with its
/// [ServerDownloadWorkStatus.error], for UI that words exceptions.
class ServerDownloadFailedException implements Exception {
  final String error;

  const ServerDownloadFailedException(this.error);

  @override
  String toString() => 'ServerDownloadFailedException: $error';
}

/// [error] as a [ServerDownloadWorkStatus.error]: a code the app explains
/// in the user's language, else the error's own text.
String serverDownloadErrorCode(Object error) => switch (error) {
  _ when isUntrustedCertificateError(error) =>
    serverDownloadUntrustedCertificateError,
  ServerDownloadHttpException(:final statusCode) =>
    '$serverDownloadStatusErrorPrefix$statusCode',
  SyncException(:final statusCode) =>
    '$serverDownloadStatusErrorPrefix$statusCode',
  SocketException() ||
  HttpException() ||
  TlsException() ||
  TimeoutException() => '${serverDownloadStatusErrorPrefix}0',
  _ => '$error',
};

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

  Future<void> deleteStatus() async {
    if (await _statusFile.exists()) await _statusFile.delete();
  }

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
  return runWorkerDownload(
    dir,
    previous: previous,
    name: fileName,
    url: input['url'] as String,
    headers: (jsonDecode(input['headers'] as String) as Map)
        .cast<String, String>(),
    client: () =>
        client ??
        serverIoClient(
          input['baseUrl'] as String,
          allowSelfSigned: input['allowSelfSigned'] as bool? ?? false,
        ),
    untrustedCertificateIsFinal: true,
  );
}

/// One run of a worker download (one WorkManager run on Android, one try of
/// the app's loop on iOS): [url] into `<name>.part` in [work]'s folder,
/// resumed, then renamed to [name]. Progress goes into the status at most
/// twice a second, then the outcome: done, else the failed attempts (1 again
/// after a run that gained bytes), failed at [serverDownloadMaxFailedAttempts]
/// or when a retry can't help. True when the download is over. Closes what
/// [client] made.
///
/// A model passes [bytes] (its pinned size: the status counts against it, and
/// a part or file that long is not fetched again), [verify] (the error of a
/// part that fails its check, which is then deleted and fails the download),
/// [marker] (written once the file is in place) and [onGiveUp]. A server book
/// learns its size from the server, and only the user can trust a certificate
/// it rejects ([untrustedCertificateIsFinal]).
Future<bool> runWorkerDownload(
  ServerDownloadWorkDir work, {
  required ServerDownloadWorkStatus? previous,
  required String name,
  required String url,
  required HttpClient Function() client,
  Map<String, String>? headers,
  int? bytes,
  Future<String?> Function(String path)? verify,
  String? marker,
  bool untrustedCertificateIsFinal = false,
  Future<void> Function(Object error)? onGiveUp,
}) async {
  final target = File(work.filePath(name));
  Future<bool> install(int size) async {
    if (marker != null) await File(work.filePath(marker)).writeAsString('ok');
    await work.writeStatus(
      ServerDownloadWorkStatus(
        state: ServerDownloadWorkState.done,
        received: size,
        total: size,
      ),
    );
    return true;
  }

  // Stopped between the rename and the marker; only a checked file is renamed.
  if (bytes != null &&
      await target.exists() &&
      await target.length() == bytes) {
    return install(bytes);
  }
  final partPath = '${target.path}.part';
  final startBytes = await _lengthOrZero(partPath);
  var received = startBytes;
  var total = bytes ?? previous?.total ?? -1;
  ServerDownloadWorkStatus running() => ServerDownloadWorkStatus(
    state: ServerDownloadWorkState.running,
    received: received,
    total: total,
  );
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  // Progress writes queue up here, so a late one can't land after (and
  // overwrite) the final status.
  var writes = Future<void>.value();
  final connection = client();
  try {
    // A complete file whose check was cut short is only checked again.
    if (startBytes != bytes) {
      await downloadResumable(
        url,
        partPath,
        client: connection,
        headers: headers,
        onProgress: (got, size) {
          received = got;
          total = bytes ?? size;
          final now = DateTime.now();
          if (now.difference(lastWrite) < const Duration(milliseconds: 500)) {
            return;
          }
          lastWrite = now;
          final status = running();
          writes = writes
              .then((_) => work.writeStatus(status))
              .catchError((_) {});
        },
      );
      await writes;
      if (verify != null) await work.writeStatus(running());
    }
    if (await verify?.call(partPath) case final error?) {
      await File(partPath).delete();
      await work.writeStatus(running().failedWith(error));
      await onGiveUp?.call(error);
      return true;
    }
    await File(partPath).rename(target.path);
    return await install(bytes ?? received);
  } catch (e) {
    await writes;
    if (!Directory(work.path).existsSync()) return true;
    if (isStorageFull(e)) {
      // ENOSPC: a retry can't fit either. Room goes first, or not even the
      // status that says so could be written. A server book's part goes; a
      // pinned-size one (gigabytes) only loses a tail, and the next run
      // continues from what is left.
      var kept = 0;
      if (bytes == null) {
        for (final path in [partPath, '$partPath.validator']) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } else {
        kept = await _cutTail(partPath);
      }
      await work.writeStatus(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.failed,
          received: kept,
          total: total,
          error: serverDownloadStorageFullError,
        ),
      );
      await onGiveUp?.call(e);
      return true;
    }
    final failedAttempts = received > startBytes
        ? 1
        : (previous?.failedAttempts ?? 0) + 1;
    final giveUp =
        (untrustedCertificateIsFinal && isUntrustedCertificateError(e)) ||
        (e is ServerDownloadHttpException && e.isPermanent) ||
        failedAttempts >= serverDownloadMaxFailedAttempts;
    await work.writeStatus(
      ServerDownloadWorkStatus(
        state: giveUp
            ? ServerDownloadWorkState.failed
            : ServerDownloadWorkState.running,
        received: received,
        total: total,
        failedAttempts: failedAttempts,
        error: serverDownloadErrorCode(e),
      ),
    );
    if (giveUp) await onGiveUp?.call(e);
    return giveUp;
  } finally {
    connection.close(force: true);
  }
}

Future<int> _lengthOrZero(String path) async {
  final file = File(path);
  return await file.exists() ? await file.length() : 0;
}

/// What a full disk cuts off a kept part: room for the status that says so,
/// with a margin for whole blocks and the file system's own records.
const _fullDiskTail = 1 << 20;

/// Cuts [_fullDiskTail] bytes (all, when shorter) off the end of the part at
/// [partPath] and returns the length left. What is left is still the start
/// of the file, so [downloadResumable] continues it.
Future<int> _cutTail(String partPath) async {
  final part = File(partPath);
  if (!await part.exists()) return 0;
  final length = await part.length();
  final kept = length > _fullDiskTail ? length - _fullDiskTail : 0;
  final raf = await part.open(mode: FileMode.append);
  try {
    await raf.truncate(kept);
  } finally {
    await raf.close();
  }
  return kept;
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
/// earlier attempt with a Range request. The resume carries `If-Range` with
/// the validator (ETag or Last-Modified) of the response that started the
/// file, so a server whose file changed in between (Kavita rebuilds a
/// chapter's zip each day) sends it whole; that, or a server that ignores
/// the range (200) or answers a different one, starts the file over.
/// [onProgress] gets the bytes on disk and the total (-1 when unknown).
/// Nothing arriving for [stallTimeout] (tests shorten it) while connecting,
/// waiting for the answer or mid-body throws a [TimeoutException], so a
/// stalled connection is retried, from the partial file, instead of hanging
/// the download for good.
Future<void> downloadResumable(
  String url,
  String partPath, {
  required HttpClient client,
  Map<String, String>? headers,
  void Function(int received, int total)? onProgress,
  Duration stallTimeout = const Duration(seconds: 30),
}) async {
  final part = File(partPath);
  final validatorFile = File('$partPath.validator');
  var existing = await _lengthOrZero(partPath);
  final uri = Uri.parse(url);
  client.connectionTimeout ??= stallTimeout;
  final request = await client.getUrl(uri);
  headers?.forEach(request.headers.set);
  if (existing > 0) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    if (await validatorFile.exists()) {
      request.headers.set('if-range', await validatorFile.readAsString());
    }
  }
  final response = await request.close().timeout(stallTimeout);

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
    // What a later resume must still match. A weak ETag can't be used in
    // If-Range; without any validator a resume is a plain Range request.
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final validator = etag != null && !etag.startsWith('W/')
        ? etag
        : response.headers.value(HttpHeaders.lastModifiedHeader);
    if (validator != null) {
      await validatorFile.writeAsString(validator);
    } else if (await validatorFile.exists()) {
      await validatorFile.delete();
    }
  } else {
    await response.drain<void>();
    if (existing > 0 &&
        (response.statusCode == HttpStatus.partialContent ||
            response.statusCode == HttpStatus.requestedRangeNotSatisfiable)) {
      // The partial file no longer matches the server's: start over.
      await part.delete();
      if (await validatorFile.exists()) await validatorFile.delete();
      return downloadResumable(
        url,
        partPath,
        client: client,
        headers: headers,
        onProgress: onProgress,
        stallTimeout: stallTimeout,
      );
    }
    throw ServerDownloadHttpException(response.statusCode);
  }

  final raf = await part.open(mode: mode);
  var received = existing;
  try {
    // Awaiting each write applies backpressure to the socket.
    await for (final chunk in response.timeout(stallTimeout)) {
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
  if (await validatorFile.exists()) await validatorFile.delete();
}

/// Downloads running in the app (server books on iOS, free books on both
/// platforms), by download key, so they can be stopped: by the user or iOS
/// ending the background task, or by a full restore
/// (`cancelServerDownloads`).
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
