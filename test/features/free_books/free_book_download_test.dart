import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/data/services/aozora_download.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider, scaffoldMessengerKey;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/saf_image_fixtures.dart';
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
  late Completer<void> requestArrived;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('free_book_download_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requestArrived = Completer<void>();
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/reader.pdf':
          response.contentLength = _pdf.length;
          response.add(_pdf);
        case '/stalls.pdf':
          // The first bytes, then nothing until the client gives up.
          response.contentLength = _pdf.length;
          response.add(_pdf.sublist(0, 100));
          await response.flush();
          requestArrived.complete();
          return;
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
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
    List<Override> overrides = const [],
  }) async {
    final db = createTestDatabase();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (aozoraBase != null)
          aozoraBaseUrlProvider.overrideWithValue(aozoraBase),
        ...overrides,
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

  /// Runs [body] as on iOS, recording what the Live Activity is sent.
  Future<void> asOnIos(
    WidgetTester tester,
    Future<void> Function(List<MethodCall> calls) body,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _backgroundWork,
      (call) async {
        calls.add(call);
        return call.method == 'begin' ? true : null;
      },
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body(calls);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _backgroundWork,
        null,
      );
    }
  }

  testWidgets('progress runs through the download, then the import', (
    tester,
  ) async {
    await asOnIos(tester, (calls) async {
      final container = await pumpApp(
        tester,
        overrides: [bookImportProvider.overrideWith(_ReportingImport.new)],
      );
      const key = 'tadoku:9';
      final progress = <double>[];
      container.listen(
        freeBookDownloadProvider.select((downloads) => downloads[key]),
        (_, value) => value == null ? null : progress.add(value),
        fireImmediately: true,
      );

      await tester.runAsync(
        () => container
            .read(freeBookDownloadProvider.notifier)
            .downloadTadoku(
              reader('http://127.0.0.1:${server.port}/reader.pdf'),
            ),
      );

      // The download fills 70%, the import the rest.
      expect(progress.first, 0);
      expect(progress, contains(closeTo(0.7, 1e-9)));
      expect(progress.where((p) => p > 0.7 && p < 1), [closeTo(0.85, 1e-9)]);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      final db = container.read(databaseProvider);
      expect((await db.select(db.books).get()).single.sourceId, key);
      // And the Live Activity ends at 100%.
      final last = calls.lastWhere((c) => c.method == 'update');
      final arguments = last.arguments as Map;
      expect(arguments['completed'], arguments['total']);
      expect(calls.last.method, 'end');
    });
  });

  testWidgets('stopping it from the Live Activity says it stopped', (
    tester,
  ) async {
    await asOnIos(tester, (_) async {
      final container = await pumpApp(tester);
      final url = 'http://127.0.0.1:${server.port}/stalls.pdf';

      await tester.runAsync(() async {
        final download = container
            .read(freeBookDownloadProvider.notifier)
            .downloadTadoku(reader(url));
        await requestArrived.future;
        // iOS, or the user, ends the background task.
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          _backgroundWork.name,
          _backgroundWork.codec.encodeMethodCall(const MethodCall('expired')),
          (_) {},
        );
        await download;
      });
      await tester.pump();

      expect(find.text(en.serverBrowseDownloadStopped), findsOneWidget);
      expect(find.text(en.freeBooksDownloadFailed), findsNothing);
      expect(container.read(freeBookDownloadProvider), isEmpty);
      expectNoLeftovers();
    });
  });

  test('an Aozora download reports the page, then each image', () async {
    const gaiji = '../../../gaiji/1-84/1-84-77.png';
    final client = MockClient(
      (request) async => request.url.path.endsWith('.png')
          ? http.Response.bytes(kTransparentPng, 200)
          : http.Response.bytes(
              utf8.encode(
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
                '<div class="main_text">KITSUNE<img src="$gaiji"/>'
                '<img src="${gaiji.replaceAll('77', '78')}"/></div>'
                '</body></html>',
              ),
              200,
            ),
    );
    final progress = <double>[];
    // Like the app's, the callback holds what can't cross to an isolate:
    // the conversion's isolates must not take it along.
    final port = ReceivePort();
    addTearDown(port.close);

    await fetchAozoraEpub(
      work,
      client,
      onProgress: (fraction) {
        port.sendPort;
        progress.add(fraction);
      },
    );

    expect(progress, [1 / 3, 2 / 3, 1.0]);
  });
}

const _backgroundWork = MethodChannel('mekuru/background_work');

/// Bytes served as a graded reader's PDF; [_ReportingImport] never reads
/// them.
final _pdf = Uint8List.fromList(List.generate(64 * 1024, (i) => i % 251));

/// An import that reports halfway and done, then adds a book row.
class _ReportingImport extends BookImportNotifier {
  @override
  Future<Book> importOne(
    String filePath, {
    required String format,
    String? title,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    final db = ref.read(databaseProvider);
    final id = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: title!, filePath: filePath));
    return (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
  }
}
