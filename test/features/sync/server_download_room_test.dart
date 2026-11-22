import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider, scaffoldMessengerKey;
import 'package:mekuru/shared/utils/format_bytes.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/free_space_fakes.dart';
import '../../shared/test_database.dart';
import '../../test_app.dart';

/// A Komga book that the server says won't fit, with the import's copy: the
/// download never starts, and the user is told how much more room it needs.
void main() {
  const ja = Locale('ja');

  // The import writes the book again before the download goes: an EPUB
  // twice (its copy and what it unzips to), anything else once.
  for (final (format, copies) in [
    (RemoteBookFormat.imageArchive, 2),
    (RemoteBookFormat.epub, 3),
  ]) {
    testWidgets('a ${format.name} book too big for the free space is never '
        'fetched, and says how much more it needs', (tester) async {
      final root = Directory.systemTemp.createTempSync('server_room_');
      useFakePathProvider(root.path);
      final requests = <String>[];
      final server = (await tester.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      server.listen((request) async {
        requests.add(request.uri.path);
        await request.response.close();
      });
      mockFreeBytes(1000);
      final db = createTestDatabase();
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final base = 'http://127.0.0.1:${server.port}';
      final client = KomgaClient(baseUrl: base, getSecret: () => 'key');
      addTearDown(() async {
        container.dispose();
        client.dispose();
        await tester.runAsync(() async {
          await server.close(force: true);
          await db.close();
        });
        root.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: const Scaffold(),
            locale: ja,
            scaffoldMessengerKey: scaffoldMessengerKey,
          ),
        ),
      );
      final connections = ServerConnectionRepository(db);
      final connection = (await tester.runAsync(() async {
        final id = await connections.create(
          serverType: 'komga',
          name: 'Home',
          baseUrl: base,
        );
        return connections.getById(id);
      }))!;

      await tester.runAsync(
        () => container
            .read(serverDownloadProvider.notifier)
            .download(
              connection: connection,
              client: client,
              book: RemoteBook(
                ids: const {'bookId': 'b1', 'seriesId': 's1'},
                title: 'Yotsuba 1',
                seriesTitle: 'Yotsuba',
                format: format,
                pageCount: 6,
                sizeBytes: 5000,
              ),
            ),
      );
      await tester.pump();

      expect(requests, isEmpty);
      expect(container.read(serverDownloadProvider), isEmpty);
      expect(root.listSync(recursive: true), isEmpty);
      expect(
        find.text(
          lookupAppLocalizations(
            ja,
          ).backupFullNotEnoughSpace(size: formatBytes(5000 * copies - 1000)),
        ),
        findsOneWidget,
      );
    });
  }
}
