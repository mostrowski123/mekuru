import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/kavita_client.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/sync/data/services/book_link_service.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/data/services/progress_sync_service.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/data/services/server_download_route.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/main.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart' hide TaskStatus;

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
        _announce((l10n) => l10n.serverLinkDropped(title: book.title)),
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
/// Transfers run in background_downloader (WorkManager on Android, a
/// background URLSession on iOS), so they keep going after the user leaves or
/// closes Mekuru. A finished file is imported here: right away while the app
/// runs, otherwise at the next launch ([resumeBackgroundDownloads]).
///
/// Servers background_downloader can't reach (see [serverDownloadRoute])
/// download with Dart instead: an accepted self-signed certificate in a
/// WorkManager job on Android, which the app watches through the job's
/// status file; on iOS that, and plain http to a domain name, in the app and
/// only while it runs.
class ServerDownloadNotifier extends Notifier<Map<String, double>> {
  final _importing = <String>{};

  /// Worker downloads being watched, by download key.
  final _workerDirs = <String, ServerDownloadWorkDir>{};
  Timer? _workerPoll;
  bool _polling = false;

  /// Folder-name prefix of in-app downloads under [serverDownloadsDir];
  /// background tasks use bare timestamps.
  static const _inAppDirPrefix = 'in_app_';

  @override
  Map<String, double> build() {
    // A restart in process (iOS full restore) builds a new notifier.
    ref.onDispose(() {
      FileDownloader().unregisterCallbacks(group: serverDownloadGroup);
      _workerPoll?.cancel();
    });
    return const {};
  }

  /// Startup: picks up transfers still running, imports files that finished
  /// while the app was closed, and requeues transfers the OS killed.
  Future<void> resumeBackgroundDownloads() async {
    // Host-side tests have no background downloader.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FileDownloader().registerCallbacks(
      group: serverDownloadGroup,
      taskStatusCallback: _onStatus,
      taskProgressCallback: _onProgress,
    );
    final running = await FileDownloader().allTasks(group: serverDownloadGroup);
    state = {...state, for (final task in running) task.taskId: 0.0};
    await FileDownloader().start();
    await _sweepInAppLeftovers();
    if (Platform.isAndroid) await _resumeWorkerDownloads();
  }

  /// Watch worker downloads from earlier sessions: import those that
  /// finished while the app was closed, report failed ones, and keep
  /// following the rest. One whose WorkManager job is gone (cancelled, or
  /// failed outside the download code) is reported as failed.
  Future<void> _resumeWorkerDownloads() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, serverDownloadsDir));
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is! Directory ||
          !p.basename(entity.path).startsWith(serverDownloadWorkDirPrefix)) {
        continue;
      }
      final dir = ServerDownloadWorkDir(entity.path);
      final job = await dir.readJob();
      final status = await dir.readStatus();
      if (job == null || status == null || _workerDirs.containsKey(job.key)) {
        await entity.delete(recursive: true);
        continue;
      }
      if (status.state == ServerDownloadWorkState.running &&
          !await Workmanager().isScheduledByUniqueName(
            serverDownloadWorkName(job.key),
          )) {
        await dir.writeStatus(
          ServerDownloadWorkStatus(
            state: ServerDownloadWorkState.failed,
            error: 'Download was interrupted',
            received: status.received,
            total: status.total,
          ),
        );
      }
      _watchWorker(job.key, dir);
    }
  }

  /// In-app downloads die with the process, so at launch any folder one left
  /// behind is garbage.
  Future<void> _sweepInAppLeftovers() async {
    if (!InAppServerDownloads.isIdle) return;
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory(p.join(support.path, serverDownloadsDir));
      if (!await root.exists()) return;
      await for (final entity in root.list()) {
        if (entity is Directory &&
            p.basename(entity.path).startsWith(_inAppDirPrefix)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (_) {
      // Best effort; the next launch tries again.
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
      final meta = {
        'connectionId': connection.id,
        'serverType': connection.serverType,
        'ids': book.ids,
        'format': book.format.name,
      };
      final route = serverDownloadRoute(
        url: request.url,
        allowSelfSigned: connection.allowSelfSignedCert,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
      );
      if (route == ServerDownloadRoute.inApp) {
        unawaited(_downloadInApp(key, connection, book, request, meta));
        return;
      }
      if (route == ServerDownloadRoute.worker) {
        await _enqueueWorker(key, connection, book, request, meta);
        return;
      }
      final queued = await FileDownloader().enqueue(
        DownloadTask(
          taskId: key,
          url: request.url,
          headers: request.headers,
          // The CBZ importer titles the book from the file name, so the file
          // must carry the real title (in its own dir — titles collide).
          filename: sanitizedExportBaseName(book.title) + book.fileExtension,
          directory:
              '$serverDownloadsDir/${DateTime.now().microsecondsSinceEpoch}',
          baseDirectory: BaseDirectory.applicationSupport,
          group: serverDownloadGroup,
          updates: Updates.statusAndProgress,
          retries: 3,
          // Carries a transfer past WorkManager's 9-minute window on Android.
          allowPause: true,
          metaData: jsonEncode(meta),
        ),
      );
      if (!queued) throw StateError('Download could not be queued');
    } catch (e) {
      state = {...state}..remove(key);
      logFailure(
        'sync.book_downloaded',
        e,
        attrs: {'server_type': connection.serverType},
      );
      _announce((l10n) => l10n.serverBrowseDownloadFailed(error: '$e'));
    }
  }

  /// Queue a Dart download as an Android WorkManager job and watch it.
  Future<void> _enqueueWorker(
    String key,
    ServerConnection connection,
    RemoteBook book,
    ({String url, Map<String, String> headers}) request,
    Map<String, dynamic> meta,
  ) async {
    final support = await getApplicationSupportDirectory();
    final dir = ServerDownloadWorkDir(
      p.join(
        support.path,
        serverDownloadsDir,
        '$serverDownloadWorkDirPrefix${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await Directory(dir.path).create(recursive: true);
    // The CBZ importer titles the book from the file name.
    final fileName = sanitizedExportBaseName(book.title) + book.fileExtension;
    try {
      await dir.writeJob(key: key, fileName: fileName, meta: meta);
      await dir.writeStatus(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.running),
      );
      await Workmanager().registerOneOffTask(
        serverDownloadWorkName(key),
        serverDownloadTaskName,
        inputData: serverDownloadWorkInput(
          dir: dir.path,
          fileName: fileName,
          url: request.url,
          headers: request.headers,
          baseUrl: connection.baseUrl,
          allowSelfSigned: connection.allowSelfSignedCert,
        ),
        tag: serverDownloadWorkTag,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {
      await Directory(dir.path).delete(recursive: true);
      rethrow;
    }
    _watchWorker(key, dir);
  }

  void _watchWorker(String key, ServerDownloadWorkDir dir) {
    _workerDirs[key] = dir;
    if (!state.containsKey(key)) state = {...state, key: 0.0};
    _workerPoll ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollWorkers()),
    );
    unawaited(_pollWorkers());
  }

  /// Follow each watched worker download through its status file.
  Future<void> _pollWorkers() async {
    if (_polling) return;
    _polling = true;
    try {
      for (final entry in [..._workerDirs.entries]) {
        final key = entry.key;
        final dir = entry.value;
        if (!ref.mounted) return;
        // A full restore deleted it to cancel.
        if (!await Directory(dir.path).exists()) {
          _stopWatching(key);
          continue;
        }
        final status = await dir.readStatus();
        if (!ref.mounted) return;
        switch (status?.state) {
          case ServerDownloadWorkState.done:
            final job = await dir.readJob();
            if (job != null && ref.mounted) {
              await _importFile(dir.filePath(job.fileName), job.meta);
            }
            await _endWorker(key, dir);
          case ServerDownloadWorkState.failed:
            final job = await dir.readJob();
            final error = status!.error ?? 'HTTP error';
            logFailure(
              'sync.book_downloaded',
              error,
              attrs: {
                'server_type': job?.meta['serverType'] as String? ?? '',
                'route': 'worker',
              },
            );
            _announce((l10n) => l10n.serverBrowseDownloadFailed(error: error));
            await _endWorker(key, dir);
          case ServerDownloadWorkState.running || null:
            final progress = status?.progress;
            if (progress != null && progress < 1) {
              state = {...state, key: progress};
            }
        }
      }
    } finally {
      _polling = false;
      if (_workerDirs.isEmpty) {
        _workerPoll?.cancel();
        _workerPoll = null;
      }
    }
  }

  Future<void> _endWorker(String key, ServerDownloadWorkDir dir) async {
    _stopWatching(key);
    try {
      await Directory(dir.path).delete(recursive: true);
    } catch (_) {
      // Best effort; launch removes what is left.
    }
  }

  void _stopWatching(String key) {
    _workerDirs.remove(key);
    if (ref.mounted) state = {...state}..remove(key);
  }

  /// A download the platform downloader can't make, run with dart:io in this
  /// process: it stops if the app is suspended or closed.
  Future<void> _downloadInApp(
    String key,
    ServerConnection connection,
    RemoteBook book,
    ({String url, Map<String, String> headers}) request,
    Map<String, dynamic> meta,
  ) async {
    final httpClient = serverIoClient(
      connection.baseUrl,
      allowSelfSigned: connection.allowSelfSignedCert,
    );
    InAppServerDownloads.start(key, httpClient);
    _announce((l10n) => l10n.serverBrowseDownloadInApp);
    Directory? dir;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory(
        p.join(
          support.path,
          serverDownloadsDir,
          '$_inAppDirPrefix${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await dir.create(recursive: true);
      // The CBZ importer titles the book from the file name.
      final path = p.join(
        dir.path,
        sanitizedExportBaseName(book.title) + book.fileExtension,
      );
      await downloadToFile(
        request.url,
        path,
        headers: request.headers,
        client: httpClient,
        onProgress: (progress) {
          if (ref.mounted && progress < 1 && state.containsKey(key)) {
            state = {...state, key: progress};
          }
        },
      );
      if (ref.mounted) await _importFile(path, meta);
    } catch (e) {
      // A full restore cancels on purpose; that is not a failure.
      if (!InAppServerDownloads.wasCancelled(key)) {
        logFailure(
          'sync.book_downloaded',
          e,
          attrs: {'server_type': connection.serverType, 'route': 'in_app'},
        );
        _announce((l10n) => l10n.serverBrowseDownloadFailed(error: '$e'));
      }
    } finally {
      InAppServerDownloads.finish(key);
      if (ref.mounted) state = {...state}..remove(key);
      try {
        await dir?.delete(recursive: true);
      } catch (_) {
        // Best effort; the next launch sweeps it.
      }
    }
  }

  void _onProgress(TaskProgressUpdate update) {
    // Negative values are status signals, and 1.0 can trail the completion.
    if (update.progress < 0 || update.progress >= 1) return;
    state = {...state, update.task.taskId: update.progress};
  }

  Future<void> _onStatus(TaskStatusUpdate update) async {
    final task = update.task;
    switch (update.status) {
      case TaskStatus.complete:
        await _import(task);
      case TaskStatus.failed || TaskStatus.notFound:
        final error =
            update.exception?.description ??
            'HTTP ${update.responseStatusCode}';
        // Server offline or Wi-Fi gone: expected, so a warning log only and
        // no Sentry issue.
        logFailure(
          'sync.book_downloaded',
          update.exception ?? error,
          attrs: {'server_type': _meta(task)['serverType'] as String},
        );
        _announce((l10n) => l10n.serverBrowseDownloadFailed(error: error));
        await _finish(task);
      case TaskStatus.canceled:
        await _finish(task);
      case TaskStatus.enqueued ||
          TaskStatus.running ||
          TaskStatus.waitingToRetry ||
          TaskStatus.paused:
        if (!state.containsKey(task.taskId)) {
          state = {...state, task.taskId: 0.0};
        }
    }
  }

  /// Import the finished file through the normal pipeline and link the new
  /// row to the server.
  Future<void> _import(Task task) async {
    // Startup can report one completion twice (the file found on disk, then
    // the stored native update): the first report imports it.
    if (!_importing.add(task.taskId)) return;
    try {
      final path = await task.filePath();
      if (await File(path).exists()) await _importFile(path, _meta(task));
    } finally {
      await _finish(task);
      _importing.remove(task.taskId);
    }
  }

  /// Import the downloaded file at [path] through the normal pipeline and
  /// link the new row to the server described by [meta].
  Future<void> _importFile(String path, Map<String, dynamic> meta) async {
    final serverType = meta['serverType'] as String;
    try {
      final repo = ref.read(bookRepositoryProvider);
      final imported = meta['format'] == RemoteBookFormat.epub.name
          ? await repo.importEpub(path)
          : await repo.importCbz(path);
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
      logUsage(
        'sync.book_downloaded',
        attrs: {'server_type': serverType, 'format': meta['format'] as String},
      );
      _announce(
        (l10n) => l10n.serverBrowseAddedToLibrary(title: imported.title),
      );
    } catch (e, st) {
      logFailure(
        'sync.book_downloaded',
        e,
        stackTrace: st,
        attrs: {'server_type': serverType},
      );
      _announce((l10n) => l10n.serverBrowseDownloadFailed(error: '$e'));
    }
  }

  Future<void> _finish(Task task) async {
    state = {...state}..remove(task.taskId);
    await FileDownloader().database.deleteRecordWithId(task.taskId);
    try {
      await File(await task.filePath()).parent.delete(recursive: true);
    } catch (_) {
      // Best effort.
    }
  }

  static Map<String, dynamic> _meta(Task task) =>
      jsonDecode(task.metaData) as Map<String, dynamic>;
}

/// Snack bar on whatever screen is showing (downloads and sync outlive the
/// screen that started them). Replaces the current one, so a batch of
/// downloads finishing together doesn't queue minutes of messages.
void _announce(String Function(AppLocalizations l10n) message) {
  final context = scaffoldMessengerKey.currentContext;
  if (context == null || !context.mounted) return;
  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message(context.l10n))));
}

final serverDownloadProvider =
    NotifierProvider<ServerDownloadNotifier, Map<String, double>>(
      ServerDownloadNotifier.new,
    );
