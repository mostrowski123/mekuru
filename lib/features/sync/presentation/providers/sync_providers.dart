import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/background_work.dart';
import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/manga/presentation/widgets/scanned_pdf_notice.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/kavita_client.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/sync/data/services/book_link_service.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/data/services/progress_sync_service.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

final serverConnectionRepositoryProvider = Provider<ServerConnectionRepository>(
  (ref) => ServerConnectionRepository(ref.watch(databaseProvider)),
);

final serverSecretStorageProvider = Provider<ServerSecretStorage>(
  (ref) => ServerSecretStorage(),
);

final serverConnectionsProvider = StreamProvider<List<ServerConnection>>(
  (ref) => ref.watch(serverConnectionRepositoryProvider).watchConnections(),
);

/// Primary remote ids of every book linked to [connectionId] — what the
/// browse screen uses to render Downloaded/Open instead of Download.
final linkedRemoteIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, int>((ref, connectionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.books)
        ..where((t) => t.serverConnectionId.equals(connectionId));
      return query.watch().map((books) {
        final ids = <String>{};
        for (final book in books) {
          final stored = ServerConnectionRepository.decodeRemoteIds(
            book.remoteIds,
          );
          if (stored == null) continue;
          final primary = ServerConnectionRepository.primaryRemoteId(stored);
          if (primary != null) ids.add(primary);
        }
        return ids;
      });
    });

/// Construct the right client for a connection. [allowSelfSigned] accepts a
/// self-signed certificate from that server; [httpClient] is for tests.
ServerClient buildServerClient({
  required ServerType type,
  required String baseUrl,
  required String Function() getSecret,
  bool allowSelfSigned = false,
  http.Client? httpClient,
}) {
  httpClient ??= allowSelfSigned
      ? serverHttpClient(baseUrl, allowSelfSigned: true)
      : null;
  return switch (type) {
    ServerType.komga => KomgaClient(
      baseUrl: baseUrl,
      getSecret: getSecret,
      httpClient: httpClient,
    ),
    ServerType.kavita => KavitaClient(
      baseUrl: baseUrl,
      getSecret: getSecret,
      httpClient: httpClient,
    ),
  };
}

/// Authenticated client for [connection], secret loaded from secure storage.
Future<ServerClient> _clientFor(Ref ref, ServerConnection connection) async {
  final secret =
      await ref.read(serverSecretStorageProvider).load(connection.id) ?? '';
  return buildServerClient(
    type: ServerType.fromStorage(connection.serverType),
    baseUrl: connection.baseUrl,
    getSecret: () => secret,
    allowSelfSigned: connection.allowSelfSignedCert,
  );
}

/// Builds a throwaway client outside the widget tree — for work that must
/// outlive a screen (the sync engine, bulk linking). Callers dispose it.
final serverClientFactoryProvider = Provider<ServerClientFactory>(
  (ref) =>
      (connection) => _clientFor(ref, connection),
);

/// Authenticated client for a stored connection; disposes with the provider.
final serverClientProvider = FutureProvider.autoDispose
    .family<ServerClient, int>((ref, connectionId) async {
      final connection = await ref
          .watch(serverConnectionRepositoryProvider)
          .getById(connectionId);
      if (connection == null) {
        throw StateError('Server connection no longer exists');
      }
      final client = await _clientFor(ref, connection);
      ref.onDispose(client.dispose);
      return client;
    });

final bookLinkServiceProvider = Provider<BookLinkService>(
  (ref) => BookLinkService(
    ref.watch(databaseProvider),
    ref.watch(serverConnectionRepositoryProvider),
  ),
);

/// Progress sync engine. Reading a book instantiates this (both reader
/// screens call syncOnOpen), which also wires the process-wide
/// progress-write hook so local reading pushes to linked servers.
final progressSyncServiceProvider = Provider<ProgressSyncService>((ref) {
  final service = ProgressSyncService(
    db: ref.watch(databaseProvider),
    connections: ref.watch(serverConnectionRepositoryProvider),
    clientFactory: ref.watch(serverClientFactoryProvider),
    onLinkDropped: (book) =>
        announce((l10n) => l10n.serverLinkDropped(title: book.title)),
  );
  BookRepository.onProgressWritten = service.schedulePush;
  ref.onDispose(() {
    BookRepository.onProgressWritten = null;
    service.dispose();
  });
  return service;
});

/// Download-and-import state: progress (0..1) per in-flight book, keyed by
/// primary remote id.
///
/// Every download runs the same Dart code (`runServerDownloadWork`): http,
/// https, or a self-signed certificate the user accepted, resuming a partial
/// file after an interruption. On Android it runs as a WorkManager job, so it
/// keeps going after Mekuru is left or closed. On iOS it runs in the app,
/// kept going in the background by [BackgroundWork]; one the app was closed
/// in the middle of continues at the next launch. Either way the download's
/// folder carries its status: this notifier follows it, imports the finished
/// book (at the next launch if it finished while the app was closed) and
/// reports failures.
class ServerDownloadNotifier extends Notifier<Map<String, double>> {
  /// Downloads being followed, by download key.
  final _followed = <String, ServerDownloadWorkDir>{};
  Timer? _poll;
  bool _checking = false;

  /// Finished downloads being imported, one after another but apart from
  /// the status check: a long PDF converts for minutes, and the other
  /// downloads' progress and imports must not wait for it.
  final _importing = <String>{};
  Future<void> _imports = Future.value();

  static bool get _onAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// On iOS a download and its import are one job, in the in-app ring and
  /// the Live Activity: the download fills this share and the import the
  /// rest, so the Live Activity keeps the app running until the book is in
  /// the library. Android's ring shows the download alone.
  static const _downloadShare = 0.7;

  void _report(String key, double progress) {
    if (!ref.mounted) return;
    state = {...state, key: progress};
    BackgroundWork.instance.progress('download:$key', progress);
  }

  @override
  Map<String, double> build() {
    // A restart in process (iOS full restore) builds a new notifier.
    ref.onDispose(() => _poll?.cancel());
    return const {};
  }

  static Future<String> _downloadsRoot() async =>
      p.join((await getApplicationSupportDirectory()).path, serverDownloadsDir);

  /// Startup: follow downloads from earlier sessions. Those that finished
  /// while the app was closed are imported, failed ones reported, running
  /// ones followed (on iOS, started again where they stopped).
  Future<void> resumeBackgroundDownloads() async {
    // Host-side tests have no app support directory.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final root = Directory(await _downloadsRoot());
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      // Not ours, e.g. left by 1.44.0's background_downloader.
      if (!p.basename(entity.path).startsWith(serverDownloadJobDirPrefix)) {
        await _deleteQuietly(entity);
        continue;
      }
      final dir = ServerDownloadWorkDir(entity.path);
      final job = await dir.readJob();
      final status = await dir.readStatus();
      if (job == null || status == null || _followed.containsKey(job.key)) {
        await _deleteQuietly(entity);
        continue;
      }
      if (status.state == ServerDownloadWorkState.running) {
        if (!_onAndroid) {
          await _restartInApp(job, dir, status);
        } else if (!await Workmanager().isScheduledByUniqueName(
          serverDownloadWorkName(job.key),
        )) {
          await dir.writeStatus(
            status.failedWith(serverDownloadInterruptedError),
          );
        }
      }
      _follow(job.key, dir);
    }
  }

  /// Queue [book] for download from [connection]. No-op while it is already
  /// queued.
  Future<void> download({
    required ServerConnection connection,
    required ServerClient client,
    required RemoteBook book,
  }) async {
    final key = ServerConnectionRepository.primaryRemoteId(book.ids);
    if (key == null || state.containsKey(key)) return;
    state = {...state, key: 0.0};
    try {
      final request = await client.downloadRequest(book);
      final dir = ServerDownloadWorkDir(
        p.join(
          await _downloadsRoot(),
          '$serverDownloadJobDirPrefix${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await Directory(dir.path).create(recursive: true);
      // The CBZ importer titles the book from the file name.
      final fileName = sanitizedExportBaseName(book.title) + book.fileExtension;
      final input = serverDownloadWorkInput(
        dir: dir.path,
        fileName: fileName,
        url: request.url,
        headers: request.headers,
        baseUrl: connection.baseUrl,
        allowSelfSigned: connection.allowSelfSignedCert,
      );
      try {
        await dir.writeJob(
          key: key,
          fileName: fileName,
          meta: {
            'connectionId': connection.id,
            'serverType': connection.serverType,
            'ids': book.ids,
            'format': book.format.name,
          },
        );
        await dir.writeStatus(
          const ServerDownloadWorkStatus(
            state: ServerDownloadWorkState.running,
          ),
        );
        if (_onAndroid) {
          await Workmanager().registerOneOffTask(
            serverDownloadWorkName(key),
            serverDownloadTaskName,
            inputData: input,
            tag: serverDownloadWorkTag,
            constraints: Constraints(networkType: NetworkType.connected),
            backoffPolicy: BackoffPolicy.exponential,
            existingWorkPolicy: ExistingWorkPolicy.replace,
          );
        } else {
          _runInApp(key, dir, input);
        }
      } catch (_) {
        await _deleteQuietly(Directory(dir.path));
        rethrow;
      }
      _follow(key, dir);
    } catch (e) {
      state = {...state}..remove(key);
      logFailure(
        'sync.book_downloaded',
        e,
        attrs: {'server_type': connection.serverType},
      );
      announce((l10n) => describeServerError(l10n, e));
    }
  }

  /// iOS: run the download in the app, kept going in the background by
  /// [BackgroundWork], with WorkManager-like retries.
  void _runInApp(
    String key,
    ServerDownloadWorkDir dir,
    Map<String, dynamic> input,
  ) {
    final workId = 'download:$key';
    BackgroundWork.instance.start(
      workId,
      BackgroundJobKind.download,
      onStopped: () => InAppServerDownloads.cancel(key),
    );
    unawaited(() async {
      // A finished download keeps its job through the import, which ends it
      // (_stopFollowing).
      var done = false;
      try {
        for (var attempt = 0; ; attempt++) {
          final client = serverIoClient(
            input['baseUrl'] as String,
            allowSelfSigned: input['allowSelfSigned'] as bool? ?? false,
          );
          InAppServerDownloads.start(key, client);
          final over = await runServerDownloadWork(input, client: client);
          InAppServerDownloads.finish(key);
          if (InAppServerDownloads.wasCancelled(key)) {
            final status = await dir.readStatus();
            if (status != null &&
                status.state != ServerDownloadWorkState.done) {
              await dir.writeStatus(
                status.failedWith(serverDownloadStoppedError),
              );
            }
            return;
          }
          if (over) {
            done =
                (await dir.readStatus())?.state == ServerDownloadWorkState.done;
            return;
          }
          await Future<void>.delayed(
            Duration(seconds: 2 << attempt.clamp(0, 5)),
          );
        }
      } catch (_) {
        // The folder went away (full restore); nothing left to record.
      } finally {
        if (!done) BackgroundWork.instance.finish(workId);
      }
    }());
  }

  /// iOS: a download the app was closed in the middle of. Its request is
  /// rebuilt from the saved connection, so nothing secret is stored with the
  /// download and an expired token is renewed; it continues from its
  /// partial file.
  Future<void> _restartInApp(
    ({String key, String fileName, Map<String, dynamic> meta}) job,
    ServerDownloadWorkDir dir,
    ServerDownloadWorkStatus status,
  ) async {
    try {
      final meta = job.meta;
      final connection = await ref
          .read(serverConnectionRepositoryProvider)
          .getById(meta['connectionId'] as int);
      if (connection == null || !connection.enabled) {
        await dir.writeStatus(
          status.failedWith(serverDownloadConnectionGoneError),
        );
        return;
      }
      final client = await _clientFor(ref, connection);
      try {
        final request = await client.downloadRequest(
          RemoteBook(
            ids: (meta['ids'] as Map).cast<String, String>(),
            title: p.basenameWithoutExtension(job.fileName),
            seriesTitle: '',
            format: RemoteBookFormat.values.byName(meta['format'] as String),
            pageCount: 0,
          ),
        );
        _runInApp(
          job.key,
          dir,
          serverDownloadWorkInput(
            dir: dir.path,
            fileName: job.fileName,
            url: request.url,
            headers: request.headers,
            baseUrl: connection.baseUrl,
            allowSelfSigned: connection.allowSelfSignedCert,
          ),
        );
      } finally {
        client.dispose();
      }
    } catch (e) {
      await dir.writeStatus(status.failedWith(serverDownloadErrorCode(e)));
    }
  }

  void _follow(String key, ServerDownloadWorkDir dir) {
    _followed[key] = dir;
    if (!state.containsKey(key)) state = {...state, key: 0.0};
    _poll ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_check()),
    );
    unawaited(_check());
  }

  /// Follow each download through its status file.
  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      for (final MapEntry(:key, value: dir) in [..._followed.entries]) {
        if (!ref.mounted) return;
        if (_importing.contains(key)) continue;
        // A full restore deleted it to cancel.
        if (!await Directory(dir.path).exists()) {
          _stopFollowing(key);
          continue;
        }
        final status = await dir.readStatus();
        if (!ref.mounted) return;
        switch (status?.state) {
          case ServerDownloadWorkState.done:
            _importing.add(key);
            _imports = _imports.then((_) => _importAndEnd(key, dir));
          case ServerDownloadWorkState.failed:
            _reportFailure(status!, await dir.readJob());
            await _end(key, dir);
          case ServerDownloadWorkState.running || null:
            final progress = status?.progress;
            if (progress != null && progress < 1) {
              _report(key, _onAndroid ? progress : progress * _downloadShare);
            }
        }
      }
    } finally {
      _checking = false;
      if (_followed.isEmpty) {
        _poll?.cancel();
        _poll = null;
      }
    }
  }

  Future<void> _importAndEnd(String key, ServerDownloadWorkDir dir) async {
    final workId = 'download:$key';
    // On iOS, a download that finished in an earlier session gets a job for
    // its import, so a long one can finish in the background. An import
    // can't stop halfway: if iOS ends the job, it finishes when the app
    // next runs.
    if (!BackgroundWork.instance.isRunning(workId)) {
      BackgroundWork.instance.start(
        workId,
        BackgroundJobKind.download,
        onStopped: () {},
      );
    }
    try {
      final job = await dir.readJob();
      if (job != null && ref.mounted) {
        await _importFile(
          dir.filePath(job.fileName),
          job.meta,
          onProgress: _onAndroid
              ? null
              : (progress) => _report(
                  key,
                  _downloadShare + (1 - _downloadShare) * progress,
                ),
        );
      }
    } catch (e, st) {
      // Caught here, so a failure can't stop the imports queued after it.
      logFailure('sync.book_downloaded', e, stackTrace: st);
    } finally {
      _importing.remove(key);
      await _end(key, dir);
    }
  }

  void _reportFailure(
    ServerDownloadWorkStatus status,
    ({String key, String fileName, Map<String, dynamic> meta})? job,
  ) {
    switch (status.error) {
      case serverDownloadStoppedError:
        announce((l10n) => l10n.serverBrowseDownloadStopped);
      case serverDownloadUntrustedCertificateError:
        announce((l10n) => l10n.serverCertificateUntrusted);
      default:
        final error = status.error ?? 'Download failed';
        // Server offline or Wi-Fi gone is expected: a warning log only.
        logFailure(
          'sync.book_downloaded',
          error,
          attrs: {'server_type': job?.meta['serverType'] as String? ?? ''},
        );
        announce((l10n) => describeServerDownloadError(l10n, error));
    }
  }

  Future<void> _end(String key, ServerDownloadWorkDir dir) async {
    _stopFollowing(key);
    await _deleteQuietly(Directory(dir.path));
  }

  void _stopFollowing(String key) {
    _followed.remove(key);
    BackgroundWork.instance.finish('download:$key');
    if (ref.mounted) state = {...state}..remove(key);
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Best effort; the next launch tries again.
    }
  }

  /// Import the downloaded file at [path] through the normal pipeline and
  /// link the new row to the server described by [meta]. [onProgress] gets
  /// the import's progress where the importer reports it (CBZ, PDF), and
  /// 1.0 once the book is in the library.
  Future<void> _importFile(
    String path,
    Map<String, dynamic> meta, {
    void Function(double progress)? onProgress,
  }) async {
    final serverType = meta['serverType'] as String;
    try {
      final repo = ref.read(bookRepositoryProvider);
      final imported = await switch (RemoteBookFormat.values.byName(
        meta['format'] as String,
      )) {
        RemoteBookFormat.epub => repo.importEpub(path),
        RemoteBookFormat.imageArchive =>
          repo.importCbz(path, onProgress: onProgress).then((cbz) => cbz.book),
        RemoteBookFormat.pdf =>
          repo.importPdf(path, onProgress: onProgress).then(explainIfScanned),
      };
      // Re-applies any pending backup data (restores progress/bookmarks for
      // books re-downloaded after a restore).
      await ref
          .read(bookImportProvider.notifier)
          .applyPendingBackupData(imported);
      await ref
          .read(serverConnectionRepositoryProvider)
          .linkBook(
            imported.id,
            meta['connectionId'] as int,
            (meta['ids'] as Map<String, dynamic>).cast<String, String>(),
          );
      // Done, also for the EPUB importer, which reports no progress.
      onProgress?.call(1.0);
      logUsage(
        'sync.book_downloaded',
        attrs: {'server_type': serverType, 'format': meta['format'] as String},
      );
      announce(
        (l10n) => l10n.serverBrowseAddedToLibrary(title: imported.title),
      );
    } catch (e, st) {
      logFailure(
        'sync.book_downloaded',
        e,
        stackTrace: st,
        attrs: {'server_type': serverType},
      );
      announce(
        (l10n) => l10n.serverBrowseDownloadFailed(
          error: importFailureReason(l10n, e),
        ),
      );
    }
  }
}

/// User-facing text for a failed server request: a hint to the self-signed
/// switch when the certificate was rejected, else why it failed.
String describeServerError(AppLocalizations l10n, Object error) =>
    isUntrustedCertificateError(error)
    ? l10n.serverCertificateUntrusted
    : l10n.serverBrowseDownloadFailed(error: serverErrorReason(l10n, error));

/// User-facing text for a server download that failed with [error], as
/// [runServerDownloadWork] or the app recorded it, in the user's language.
/// An error with no code is shown as it is.
String describeServerDownloadError(AppLocalizations l10n, String error) {
  if (error == serverDownloadInterruptedError) {
    return l10n.serverBrowseDownloadInterrupted;
  }
  if (error == serverDownloadConnectionGoneError) {
    return l10n.serverBrowseDownloadFailed(
      error: l10n.serverErrorConnectionGone,
    );
  }
  final status = serverDownloadErrorStatus(error);
  return l10n.serverBrowseDownloadFailed(
    error: status == null
        ? error
        : serverErrorReason(l10n, SyncException(status, error)),
  );
}

/// Why a Komga or Kavita request failed, in the user's language: a rejected
/// sign-in, an unreachable server or the HTTP status. Any other error is
/// shown as it is.
String serverErrorReason(AppLocalizations l10n, Object error) =>
    switch (error) {
      SyncException(isAuthFailure: true) => l10n.serverErrorSignInRejected,
      SyncException(isUnreachable: true) => l10n.serverErrorUnreachable,
      SyncException(:final statusCode) => l10n.serverErrorStatus(
        status: statusCode,
      ),
      _ => '$error',
    };

final serverDownloadProvider =
    NotifierProvider<ServerDownloadNotifier, Map<String, double>>(
      ServerDownloadNotifier.new,
    );
