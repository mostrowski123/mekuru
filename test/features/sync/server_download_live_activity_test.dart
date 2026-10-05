import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/saf_image_fixtures.dart';
import '../../shared/test_database.dart';

/// A Komga book downloaded on iOS: the Live Activity carries it through
/// the import, not just the download, and the in-app ring agrees.
void main() {
  // Real sockets for the loopback server; the test binding mocks them.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const backgroundWork = MethodChannel('mekuru/background_work');

  late Directory tempDir;
  late HttpServer server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('server_live_activity_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final archive = Archive();
    for (var i = 1; i <= 6; i++) {
      archive.addFile(
        ArchiveFile('00$i.png', kTransparentPng.length, kTransparentPng),
      );
    }
    final cbz = Uint8List.fromList(ZipEncoder().encode(archive));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/api/v1/books/b1/file') {
        request.response.contentLength = cbz.length;
        request.response.add(cbz);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  test(
    'on iOS the Live Activity ends only once the book is imported',
    () async {
      final db = createTestDatabase();
      final connections = ServerConnectionRepository(db);
      final base = 'http://127.0.0.1:${server.port}';
      final connectionId = await connections.create(
        serverType: 'komga',
        name: 'Home',
        baseUrl: base,
      );
      final connection = (await connections.getById(connectionId))!;
      final client = KomgaClient(baseUrl: base, getSecret: () => 'key');
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );

      final calls = <MethodCall>[];
      int? booksWhenEnded;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backgroundWork, (call) async {
            calls.add(call);
            if (call.method == 'end') {
              booksWhenEnded = (await db.select(db.books).get()).length;
            }
            return call.method == 'begin' ? true : null;
          });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(backgroundWork, null);
        container.dispose();
        client.dispose();
        await db.close();
      });

      final ring = <double>[];
      container.listen(
        serverDownloadProvider.select((downloads) => downloads['b1']),
        (_, progress) => progress == null ? null : ring.add(progress),
      );

      await container
          .read(serverDownloadProvider.notifier)
          .download(
            connection: connection,
            client: client,
            book: const RemoteBook(
              ids: {'bookId': 'b1', 'seriesId': 's1'},
              title: 'Yotsuba 1',
              seriesTitle: 'Yotsuba',
              format: RemoteBookFormat.imageArchive,
              pageCount: 6,
            ),
          );
      for (var i = 0; i < 300 && booksWhenEnded == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // The Live Activity lasted until the book was in the library...
      expect(booksWhenEnded, 1);
      expect(await connections.booksLinkedTo(connectionId), hasLength(1));
      // ...and ended at 100%.
      final last = calls.lastWhere((call) => call.method == 'update');
      final arguments = last.arguments as Map;
      expect(arguments['completed'], arguments['total']);
      expect(calls.where((call) => call.method == 'end'), hasLength(1));
      // The ring showed the import too, after the download's share.
      expect(ring.where((progress) => progress > 0.7), isNotEmpty);
      for (var i = 1; i < ring.length; i++) {
        expect(ring[i], greaterThanOrEqualTo(ring[i - 1]));
      }
    },
  );
}
