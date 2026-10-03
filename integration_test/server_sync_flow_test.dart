import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/data/services/progress_sync_service.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

import 'shared/self_signed_cert.dart';
import 'shared/test_infrastructure.dart';

/// Minimal JPEG-looking bytes; dimensions come from the mokuro manifest.
final _fakeJpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

/// In-process fake Komga server: one library, one series, one CBZ book
/// (images + embedded .mokuro), with mutable read progress.
class FakeKomga {
  late final HttpServer _server;
  late final List<int> cbzBytes;

  Map<String, dynamic>? readProgress;
  Map<String, dynamic>? lastProgressPatch;
  String? lastApiKey;

  bool _secure = false;

  String get baseUrl =>
      '${_secure ? 'https' : 'http'}://127.0.0.1:${_server.port}';

  /// With [selfSigned], serve HTTPS with a certificate no device trusts.
  Future<void> start({bool selfSigned = false}) async {
    final archive = Archive();
    for (final name in ['0001.jpg', '0002.jpg', '0003.jpg']) {
      archive.addFile(ArchiveFile(name, _fakeJpeg.length, _fakeJpeg));
    }
    final mokuro = utf8.encode(
      jsonEncode({
        'version': '0.2.1',
        'title': 'よつばと！ 1',
        'volume': 'よつばと！ 1',
        'pages': [
          for (var i = 1; i <= 3; i++)
            {
              'img_path': '000$i.jpg',
              'img_width': 800,
              'img_height': 1200,
              'blocks': [
                {
                  'box': [10, 10, 200, 400],
                  'vertical': true,
                  'font_size': 24,
                  'lines_coords': [
                    [
                      [10, 10],
                      [200, 10],
                      [200, 400],
                      [10, 400],
                    ],
                  ],
                  'lines': ['こんにちは'],
                },
              ],
            },
        ],
      }),
    );
    archive.addFile(ArchiveFile('よつばと！ 1.mokuro', mokuro.length, mokuro));
    cbzBytes = ZipEncoder().encode(archive);

    _secure = selfSigned;
    _server = selfSigned
        ? await HttpServer.bindSecure(
            InternetAddress.loopbackIPv4,
            0,
            SecurityContext()
              ..useCertificateChainBytes(utf8.encode(selfSignedCertPem))
              ..usePrivateKeyBytes(utf8.encode(selfSignedKeyPem)),
          )
        : await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    lastApiKey = request.headers.value('X-API-Key');
    final path = request.uri.path;

    Future<void> json(Object body) async {
      request.response.headers.contentType = ContentType.json;
      request.response.add(utf8.encode(jsonEncode(body)));
      await request.response.close();
    }

    if (path == '/api/v1/libraries') {
      return json([
        {'id': 'lib1', 'name': 'Manga'},
      ]);
    }
    if (path == '/api/v1/series') {
      return json({
        'content': [
          {
            'id': 's1',
            'name': 'yotsuba',
            'booksCount': 1,
            'metadata': {'title': 'よつばと！'},
          },
        ],
        'last': true,
      });
    }
    if (path == '/api/v1/series/s1/books') {
      return json({
        'content': [
          {
            'id': 'b1',
            'name': 'よつばと！ 1',
            'media': {'mediaProfile': 'DIVINA', 'pagesCount': 3},
            'metadata': {'title': 'よつばと！ 1'},
          },
        ],
        'last': true,
      });
    }
    if (path == '/api/v1/books/b1/file') {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(cbzBytes);
      await request.response.close();
      return;
    }
    if (path == '/api/v1/books/b1' && request.method == 'GET') {
      return json({'id': 'b1', 'readProgress': readProgress});
    }
    if (path == '/api/v1/books/b1/read-progress' && request.method == 'PATCH') {
      lastProgressPatch =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}

/// The book the download notifier imported and linked to [connectionId].
Future<Book> _linkedBook(
  ServerConnectionRepository connections,
  int connectionId,
) async {
  // Up to a minute: on Android a self-signed download first starts a
  // WorkManager job with its own Flutter engine.
  for (var i = 0; i < 300; i++) {
    final linked = await connections.booksLinkedTo(connectionId);
    if (linked.isNotEmpty) return linked.single;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('The downloaded book was never imported');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browse, download, and progress sync against a fake Komga', (
    tester,
  ) async {
    final komga = FakeKomga();
    await komga.start();
    final db = createTestDatabase();
    final connections = ServerConnectionRepository(db);
    final bookRepo = BookRepository(db);
    final client = KomgaClient(
      baseUrl: komga.baseUrl,
      getSecret: () => 'integration-key',
    );
    final sync = ProgressSyncService(
      db: db,
      connections: connections,
      clientFactory: (_) async => KomgaClient(
        baseUrl: komga.baseUrl,
        getSecret: () => 'integration-key',
      ),
    );
    addTearDown(() async {
      sync.dispose();
      client.dispose();
      await db.close();
      await komga.stop();
    });

    final connectionId = await connections.create(
      serverType: 'komga',
      name: 'Fake',
      baseUrl: komga.baseUrl,
    );
    final connection = (await connections.getById(connectionId))!;

    // ── Browse ──
    await client.testConnection();
    expect(komga.lastApiKey, 'integration-key');
    final libraries = await client.listLibraries();
    final series = await client.listSeries(libraries.single.id);
    expect(series.single.title, 'よつばと！');
    final books = await client.listBooks(series.single);
    expect(books.single.format, RemoteBookFormat.imageArchive);

    // ── Download through the background downloader and the real import ──
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final downloads = container.read(serverDownloadProvider.notifier);
    await downloads.resumeBackgroundDownloads();
    await downloads.download(
      connection: connection,
      client: client,
      book: books.single,
    );
    final imported = await _linkedBook(connections, connectionId);
    expect(container.read(serverDownloadProvider), isEmpty);

    // The embedded .mokuro made it through: pages carry OCR blocks, which
    // is exactly what tap-to-lookup renders.
    final cache =
        jsonDecode(
              await File(
                p.join(imported.filePath, 'pages_cache.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(cache['ocrSource'], 'mokuro');
    final pages = cache['pages'] as List;
    expect(pages, hasLength(3));
    expect(
      ((pages.first as Map<String, dynamic>)['blocks'] as List),
      isNotEmpty,
    );

    // ── Local reading pushes to the server ──
    await bookRepo.updateProgress(imported.id, '1', progress: 0.5);
    await sync.pushBook(imported.id);
    expect(komga.lastProgressPatch, {'page': 2, 'completed': false});

    // ── A newer server state is adopted on open ──
    komga.readProgress = {
      'page': 3,
      'completed': true,
      'lastModified': DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    };
    final opened = await (db.select(
      db.books,
    )..where((t) => t.id.equals(imported.id))).getSingle();
    final remote = await sync.syncOnOpen(opened);
    expect(remote, isNotNull);
    final updated = await (db.select(
      db.books,
    )..where((t) => t.id.equals(imported.id))).getSingle();
    expect(updated.lastReadCfi, '2');
    expect(updated.readProgress, 1.0);

    // ── Deleting the connection leaves the book and progress intact ──
    await connections.delete(connectionId);
    final after = await (db.select(
      db.books,
    )..where((t) => t.id.equals(imported.id))).getSingle();
    expect(after.serverConnectionId, null);
    expect(after.lastReadCfi, '2');
    expect(after.readProgress, 1.0);
    expect(
      await File(p.join(after.filePath, 'pages_cache.json')).exists(),
      isTrue,
    );
    expect(connection.id, connectionId);
  });

  testWidgets('backup carries server links and restores them disabled', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final connections = ServerConnectionRepository(db);
    final connectionId = await connections.create(
      serverType: 'komga',
      name: 'Fake',
      baseUrl: 'http://127.0.0.1:9999',
    );
    final bookId = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: 'linked', filePath: '/x'));
    await connections.linkBook(bookId, connectionId, {
      'bookId': 'b1',
      'seriesId': 's1',
    });

    final manifest = await BackupService(db, BookMatchService()).createBackup();
    final encoded = BackupSerializer.encode(manifest);

    final freshDb = createTestDatabase();
    addTearDown(freshDb.close);
    final restore = RestoreService(
      freshDb,
      BookMatchService(),
      PendingBookDataRepository(freshDb),
    );
    final result = await restore.restoreBooks(BackupSerializer.decode(encoded));
    expect(result.pending, 1);

    final restoredConnections = await freshDb
        .select(freshDb.serverConnections)
        .get();
    expect(restoredConnections, hasLength(1));
    expect(restoredConnections.single.enabled, isFalse);
    final pendingRows = await freshDb.select(freshDb.pendingBookDatas).get();
    final entry = BackupSerializer.decodeBookEntry(pendingRows.single.dataJson);
    expect(entry.serverLink!.connectionId, restoredConnections.single.id);
  });

  testWidgets(
    'browse and download from a Komga with a self-signed certificate',
    (tester) async {
      final komga = FakeKomga();
      await komga.start(selfSigned: true);
      final db = createTestDatabase();
      final connections = ServerConnectionRepository(db);
      addTearDown(() async {
        await db.close();
        await komga.stop();
      });

      // Without the switch the certificate is refused.
      final strict = buildServerClient(
        type: ServerType.komga,
        baseUrl: komga.baseUrl,
        getSecret: () => 'integration-key',
      );
      addTearDown(strict.dispose);
      await expectLater(strict.testConnection(), throwsA(isA<Exception>()));

      final connectionId = await connections.create(
        serverType: 'komga',
        name: 'Self-signed',
        baseUrl: komga.baseUrl,
        allowSelfSignedCert: true,
      );
      final connection = (await connections.getById(connectionId))!;
      final client = buildServerClient(
        type: ServerType.komga,
        baseUrl: komga.baseUrl,
        getSecret: () => 'integration-key',
        allowSelfSigned: connection.allowSelfSignedCert,
      );
      addTearDown(client.dispose);

      await client.testConnection();
      final libraries = await client.listLibraries();
      final series = await client.listSeries(libraries.single.id);
      final books = await client.listBooks(series.single);

      // background_downloader can't accept the certificate, so this
      // downloads with Dart (a WorkManager job on Android, in the app on
      // iOS), then imports like any other download.
      if (Platform.isAndroid) {
        await Workmanager().initialize(ocrWorkerCallbackDispatcher);
      }
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final downloads = container.read(serverDownloadProvider.notifier);
      await downloads.resumeBackgroundDownloads();
      await downloads.download(
        connection: connection,
        client: client,
        book: books.single,
      );
      var watching = container;
      if (Platform.isAndroid) {
        // Close the app's side right away, as if Mekuru were swiped away:
        // the WorkManager job carries on, and the next launch imports what
        // it downloaded.
        container.dispose();
        watching = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(watching.dispose);
        await watching
            .read(serverDownloadProvider.notifier)
            .resumeBackgroundDownloads();
      }
      final imported = await _linkedBook(connections, connectionId);
      expect(imported.title, 'よつばと！ 1');
      expect(komga.lastApiKey, 'integration-key');
      expect(watching.read(serverDownloadProvider), isEmpty);
    },
  );
}
