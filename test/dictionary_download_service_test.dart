import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'shared/fake_download_notifiers.dart' show mockWifiConnected;
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
      } else if (request.uri.path == '/slow.zip') {
        // Half the zip, a pause, then the rest.
        response.contentLength = zip.length;
        response.add(zip.sublist(0, zip.length ~/ 2));
        await response.flush();
        await Future<void>.delayed(const Duration(seconds: 4));
        response.add(zip.sublist(zip.length ~/ 2));
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
    expect(meta.revision, 'JMnedict.2026-10-03');
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

  test('a download a closed app left behind is deleted by the next', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final left = File('${tempDir.path}/download_1_jitendex-yomitan.zip')
      ..writeAsBytesSync([0])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final running = File('${tempDir.path}/download_2_JMdict_spanish.zip')
      ..writeAsBytesSync([0]);

    await DictionaryDownloadService.downloadAndImportUrl(
      url: urlFor('/JMnedict.zip'),
      asset: 'jmnedict',
      importer: DictionaryImporter(DictionaryRepository(db)),
    );

    expect(left.existsSync(), isFalse);
    expect(running.existsSync(), isTrue);
  });

  test('a download started on Wi-Fi stops when Wi-Fi goes', () async {
    mockWifiConnected(true);
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);

    final download = DictionaryDownloadService.downloadAndImportUrl(
      url: urlFor('/slow.zip'),
      asset: 'jmnedict',
      importer: DictionaryImporter(repo),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    mockWifiConnected(false);

    await expectLater(download, throwsA(isA<WifiLostException>()));
    expect(await repo.getAllDictionaries(), isEmpty);
  });

  test('on iOS a download is background work, and stops when iOS ends '
      'it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    const channel = MethodChannel('mekuru/background_work');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'begin' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final download = DictionaryDownloadService.downloadAndImportUrl(
      url: urlFor('/JMnedict.zip'),
      asset: 'jmnedict',
      importer: DictionaryImporter(repo),
    );
    // iOS ends the background task before the download gets going.
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('expired')),
      (_) {},
    );

    await expectLater(download, throwsA(isA<DownloadStoppedException>()));
    expect(calls.first, 'begin');
    expect(await repo.getAllDictionaries(), isEmpty);
  });

  test('a stop that comes once the import is saved does not undo it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    const channel = MethodChannel('mekuru/background_work');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'begin' ? true : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await DictionaryDownloadService.downloadAndImportUrl(
      url: urlFor('/JMnedict.zip'),
      asset: 'jmnedict',
      importer: _StopAfterImport(
        repo,
        () => messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('expired')),
          (_) {},
        ),
      ),
    );

    expect(await repo.getAllDictionaries(), hasLength(1));
  });
}

/// Lets iOS end the background task right after the import commits.
class _StopAfterImport extends DictionaryImporter {
  _StopAfterImport(super.repository, this.afterImport);

  final Future<void> Function() afterImport;

  @override
  Future<int> importFromFile(
    String filePath, {
    void Function(int processed, int total)? onProgress,
    void Function()? onFinishing,
  }) async {
    final count = await super.importFromFile(
      filePath,
      onProgress: onProgress,
      onFinishing: onFinishing,
    );
    await afterImport();
    return count;
  }
}
