import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/analytics_service.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/kavita_client.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/data/services/progress_sync_service.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/main.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

/// Construct the right client for a connection. [httpClient] is for tests.
ServerClient buildServerClient({
  required ServerType type,
  required String baseUrl,
  required String Function() getSecret,
  http.Client? httpClient,
}) => switch (type) {
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

/// Authenticated client for a stored connection; disposes with the provider.
final serverClientProvider = FutureProvider.autoDispose
    .family<ServerClient, int>((ref, connectionId) async {
      final connection = await ref
          .watch(serverConnectionRepositoryProvider)
          .getById(connectionId);
      if (connection == null) {
        throw StateError('Server connection no longer exists');
      }
      final secret =
          await ref.watch(serverSecretStorageProvider).load(connectionId) ?? '';
      final client = buildServerClient(
        type: ServerType.fromStorage(connection.serverType),
        baseUrl: connection.baseUrl,
        getSecret: () => secret,
      );
      ref.onDispose(client.dispose);
      return client;
    });

/// Progress sync engine. Reading a book instantiates this (both reader
/// screens call syncOnOpen), which also wires the process-wide
/// progress-write hook so local reading pushes to linked servers.
final progressSyncServiceProvider = Provider<ProgressSyncService>((ref) {
  final service = ProgressSyncService(
    db: ref.watch(databaseProvider),
    connections: ref.watch(serverConnectionRepositoryProvider),
    clientFactory: (connection) async {
      final secret =
          await ref.read(serverSecretStorageProvider).load(connection.id) ?? '';
      return buildServerClient(
        type: ServerType.fromStorage(connection.serverType),
        baseUrl: connection.baseUrl,
        getSecret: () => secret,
      );
    },
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
class ServerDownloadNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  /// Download [book] from [connection], import it through the normal
  /// pipeline, and link the new row to the server. Returns the imported
  /// book, or null when this book is already being downloaded.
  Future<Book?> download({
    required ServerConnection connection,
    required ServerClient client,
    required RemoteBook book,
  }) async {
    final key = ServerConnectionRepository.primaryRemoteId(book.ids);
    if (key == null || state.containsKey(key)) return null;
    state = {...state, key: 0.0};
    Directory? tempDir;
    try {
      // The CBZ importer titles the book from the file name, so the temp
      // file must carry the real title (in its own dir — titles collide).
      tempDir = await Directory(
        p.join(
          (await getTemporaryDirectory()).path,
          'server_dl_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      final fileName = _sanitizeFileName(book.title) + book.fileExtension;
      final destPath = p.join(tempDir.path, fileName);

      await client.downloadBook(
        book,
        destPath,
        onProgress: (progress) => state = {...state, key: progress},
      );

      final importNotifier = ref.read(bookImportProvider.notifier);
      final repo = ref.read(bookRepositoryProvider);
      final imported = book.format == RemoteBookFormat.epub
          ? await repo.importEpub(destPath)
          : await repo.importCbz(destPath);
      // Re-applies any pending backup data (restores progress/bookmarks for
      // books re-downloaded after a restore).
      await importNotifier.applyPendingBackupData(imported);
      await ref
          .read(serverConnectionRepositoryProvider)
          .linkBook(imported.id, connection.id, book.ids);
      AnalyticsService.instance.logEvent('server_book_downloaded', {
        'server_type': connection.serverType,
        'format': book.format.name,
      });
      return imported;
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      rethrow;
    } finally {
      state = {...state}..remove(key);
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Best-effort temp cleanup only.
        }
      }
    }
  }

  static String _sanitizeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'book' : cleaned;
  }
}

final serverDownloadProvider =
    NotifierProvider<ServerDownloadNotifier, Map<String, double>>(
      ServerDownloadNotifier.new,
    );
