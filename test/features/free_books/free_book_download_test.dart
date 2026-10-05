import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider, scaffoldMessengerKey;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/test_database.dart';
import '../../test_app.dart';

/// Free-book downloads that fail, against a loopback server: what the
/// reader is told, and that nothing is left behind.
void main() {
  // Real sockets for the loopback server; the test binding mocks them.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final en = lookupAppLocalizations(const Locale('en'));
  late Directory tempDir;
  late HttpServer server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('free_book_download_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  TadokuBook reader(String pdfUrl) => TadokuBook(
    id: 9,
    title: 'がっこう',
    titleReading: 'がっこう',
    level: 1,
    coverUrl: Uri.parse('$pdfUrl.png'),
    pdfUrl: Uri.parse(pdfUrl),
    pageCount: 2,
    charCount: 0,
    hasAudio: false,
    hasText: true,
  );

  final work = AozoraWork(
    id: 1,
    title: '手袋を買いに',
    titleReading: 'てぶくろをかいに',
    author: '新美 南吉',
    authorReading: 'にいみ なんきち',
    xhtmlPath: '000001/files/1_1.html',
    genre: AozoraGenre.children,
    spelling: AozoraSpelling.modern,
    charCount: 5000,
    jlptEstimate: 4,
    popularity: 1,
  );

  /// An app showing announcements, around [container]'s providers.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    String? aozoraBase,
  }) async {
    final db = createTestDatabase();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (aozoraBase != null)
          aozoraBaseUrlProvider.overrideWithValue(aozoraBase),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: const Scaffold(),
          scaffoldMessengerKey: scaffoldMessengerKey,
        ),
      ),
    );
    return container;
  }

  /// Nothing the download wrote is left in the temporary folder.
  void expectNoLeftovers() =>
      expect(tempDir.listSync().whereType<File>().map((f) => f.path), isEmpty);

  testWidgets('a book the site does not have fails as a download', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    final url = 'http://127.0.0.1:${server.port}/b9.pdf';

    await tester.runAsync(
      () => container
          .read(freeBookDownloadProvider.notifier)
          .downloadTadoku(reader(url)),
    );
    await tester.pump();

    expect(find.text(en.freeBooksDownloadFailed), findsOneWidget);
    expect(container.read(freeBookDownloadProvider), isEmpty);
    expectNoLeftovers();
  });

  testWidgets('a TLS failure is a failed download, not a failed import', (
    tester,
  ) async {
    // https to a plain-HTTP server: the handshake fails, as it does behind
    // a captive portal.
    final base = 'https://127.0.0.1:${server.port}';
    final container = await pumpApp(tester, aozoraBase: '$base/cards/');
    final downloads = container.read(freeBookDownloadProvider.notifier);

    await tester.runAsync(
      () => downloads.downloadTadoku(reader('$base/b.pdf')),
    );
    await tester.pump();
    expect(find.text(en.freeBooksDownloadFailed), findsOneWidget);

    scaffoldMessengerKey.currentState!.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.runAsync(() => downloads.downloadAozora(work));
    await tester.pump();
    expect(find.text(en.freeBooksDownloadFailed), findsOneWidget);
    expect(find.text(en.freeBooksImportFailed), findsNothing);
    expect(container.read(freeBookDownloadProvider), isEmpty);
    expectNoLeftovers();
  });
}
