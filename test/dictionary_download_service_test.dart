import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'shared/fake_path_provider.dart';
import 'shared/test_database.dart';

/// Downloads a real zip from a loopback server and imports it.
void main() {
  // The free-space channel needs a binding; the loopback server needs real
  // sockets, which the test binding replaces with a mock.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  late HttpServer server;
  var requests = 0;

  String urlFor(String path) => 'http://127.0.0.1:${server.port}$path';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('dictionary_download_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    final index = utf8.encode(
      jsonEncode({
        'title': 'JMnedict [2026-10-03]',
        'format': 3,
        'revision': 'JMnedict.2026-10-03',
        'isUpdatable': true,
        'indexUrl': 'https://example.com/JMnedict.json',
      }),
    );
    final bank = utf8.encode(
      jsonEncode([
        [
          '山田',
          'やまだ',
          '',
          '',
          0,
          ['Yamada (surname)'],
          1,
          '',
        ],
      ]),
    );
    final zip = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('index.json', index.length, index))
        ..addFile(ArchiveFile('term_bank_1.json', bank.length, bank)),
    );

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    server.listen((request) async {
      requests++;
      final response = request.response;
      if (request.uri.path == '/JMnedict.zip') {
        response.contentLength = zip.length;
        response.add(zip);
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  test('downloads, imports, and reports progress through to 1.0', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    final progress = <double>[];

    await DictionaryDownloadService.downloadAndImportUrl(
      url: urlFor('/JMnedict.zip'),
      asset: 'jmnedict',
      importer: DictionaryImporter(repo),
      onProgress: progress.add,
    );

    final meta = (await repo.getAllDictionaries()).single;
    expect(meta.name, 'JMnedict [2026-10-03]');
    expect(meta.indexUrl, 'https://example.com/JMnedict.json');
    expect(progress.last, 1.0);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(progress.any((p) => p > 0.7 && p < 1.0), isTrue);
    // The downloaded zip does not linger in the temporary directory.
    expect(tempDir.listSync().whereType<File>(), isEmpty);
  });

  test('a failed download imports nothing', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);

    await expectLater(
      DictionaryDownloadService.downloadAndImportUrl(
        url: urlFor('/missing.zip'),
        asset: 'missing',
        importer: DictionaryImporter(repo),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await repo.getAllDictionaries(), isEmpty);
  });

  test('an install that needs more room than is free stops before '
      'downloading', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    const safChannel = MethodChannel('mekuru/android_saf');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      safChannel,
      (call) async => call.method == 'getFreeBytes' ? 1000000 : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(safChannel, null));

    await expectLater(
      DictionaryDownloadService.downloadAndImportUrl(
        url: urlFor('/JMnedict.zip'),
        asset: 'jmnedict',
        importer: DictionaryImporter(repo),
        requiredBytes: 100000000,
      ),
      throwsA(
        isA<InsufficientSpaceException>().having(
          (e) => e.neededBytes,
          'neededBytes',
          99000000,
        ),
      ),
    );
    expect(requests, 0);
    expect(await repo.getAllDictionaries(), isEmpty);
  });
}
