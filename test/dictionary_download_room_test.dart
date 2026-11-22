import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'shared/fake_path_provider.dart';
import 'shared/loopback_http.dart';
import 'shared/test_database.dart';

/// A way into a dictionary download, with the zip and the database growth
/// its dictionary declares, in bytes. [start] answers what stopped the
/// download, null when it imported.
typedef _Entry = ({
  String name,
  int zip,
  int growth,
  String title,
  Future<Object?> Function(ProviderContainer c) start,
});

Future<Object?> _failure(Future<void> download) async {
  try {
    await download;
    return null;
  } catch (e) {
    return e;
  }
}

final _entries = <_Entry>[
  (
    name: 'the JMdict English tile',
    zip: 15_600_000,
    growth: 281_400_000,
    title: 'JMdict (English) [2026-11-22]',
    start: (c) => _failure(
      YomitanDictDownloadService.downloadAndImport(
        type: YomitanDictType.jmdictEnglish,
        repository: c.read(dictionaryRepositoryProvider),
        importer: c.read(dictionaryImporterProvider),
        network: NetworkConsent.mobileData,
      ),
    ),
  ),
  (
    name: 'the JPDB tile',
    zip: 6_000_000,
    growth: 39_100_000,
    title: JpdbFreqDownloadService.dictionaryName,
    start: (c) => _failure(
      JpdbFreqDownloadService.downloadAndImport(
        repository: c.read(dictionaryRepositoryProvider),
        importer: c.read(dictionaryImporterProvider),
        network: NetworkConsent.mobileData,
      ),
    ),
  ),
  (
    name: 'a catalog dictionary',
    zip: 1_300_000,
    growth: 14_000_000,
    title: 'JMdict (Spanish) [2026-11-22]',
    start: (c) async {
      final download = catalogDownloadProvider(CatalogDictionary.jmdictSpanish);
      await c.read(download.notifier).download(NetworkConsent.mobileData);
      return c.read(download).outcome?.error;
    },
  ),
];

/// A one-entry Yomitan zip titled [title].
List<int> _zip(String title) {
  final index = utf8.encode(
    jsonEncode({'title': title, 'format': 3, 'revision': '$title.rev'}),
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
  return ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('index.json', index.length, index))
      ..addFile(ArchiveFile('term_bank_1.json', bank.length, bank)),
  );
}

/// How much free space a dictionary download asks for before it fetches
/// anything, through each way into one: the zip, the database's growth, and
/// the import's journal, which is no larger than the database file now.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const saf = MethodChannel('mekuru/android_saf');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LoopbackHttp http;
  late Directory root;
  late AppDatabase db;
  late ProviderContainer container;
  int? free;

  setUpAll(() async => http = await LoopbackHttp.start());
  tearDownAll(() => http.close());

  setUp(() {
    http.reset();
    root = Directory.systemTemp.createTempSync('dictionary_room_');
    PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
    db = createTestDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    messenger.setMockMethodCallHandler(
      saf,
      (call) async => call.method == 'getFreeBytes' ? free : null,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(saf, null);
    container.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// Puts the app's database file, which the in-memory database leaves out,
  /// at [bytes] long.
  void databaseFile(int bytes) {
    final file = File(
      p.join(root.path, AppDatabase.databaseFileName),
    ).openSync(mode: FileMode.write);
    file.truncateSync(bytes);
    file.closeSync();
  }

  for (final entry in _entries) {
    /// The free bytes [entry] asks for: one byte free, and how many more it
    /// says it needs.
    Future<int> room() async {
      free = 1;
      final failure = await entry.start(container);
      expect(http.requests, isEmpty);
      return (failure! as InsufficientSpaceException).neededBytes + 1;
    }

    // What it asks for on top of the zip and the growth at the least.
    final margin = entry.growth ~/ 20;

    group(entry.name, () {
      test('into an almost empty database, asks for the zip, the growth and '
          'a twentieth of the growth', () async {
        databaseFile(4096);
        expect(await room(), entry.zip + entry.growth + margin);
      });

      test('into a database smaller than the growth, asks for the zip, the '
          'growth and the database', () async {
        databaseFile(entry.growth ~/ 2);
        expect(await room(), entry.zip + entry.growth + entry.growth ~/ 2);
      });

      test(
        'with that much free, downloads and imports the dictionary',
        () async {
          databaseFile(4096);
          free = entry.zip + entry.growth + margin;
          http.handler = serve(_zip(entry.title));

          expect(await entry.start(container), isNull);
          final dictionaries = await container
              .read(dictionaryRepositoryProvider)
              .getAllDictionaries();
          expect([for (final d in dictionaries) d.name], [entry.title]);
        },
      );

      test('with a byte less than the zip and the growth, fetches nothing '
          'and says how much more it needs', () async {
        databaseFile(4096);
        free = entry.zip + entry.growth - 1;

        expect(
          await entry.start(container),
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            margin + 1,
          ),
        );
        expect(http.requests, isEmpty);
      });

      test('into a database as large as the growth, asks for the zip and '
          'twice the growth', () async {
        databaseFile(entry.growth);
        expect(await room(), entry.zip + 2 * entry.growth);
      });

      test('when the database file cannot be measured, asks for the zip and '
          'twice the growth', () async {
        expect(await room(), entry.zip + 2 * entry.growth);
      });
    });
  }
}
