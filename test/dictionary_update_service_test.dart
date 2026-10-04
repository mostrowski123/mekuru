import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_update_service.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'shared/fake_path_provider.dart';
import 'shared/test_database.dart';

void main() {
  // The background-work channel needs a binding; the loopback server needs
  // real sockets, which the test binding replaces with a mock.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late AppDatabase db;
  late DictionaryRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
  });

  tearDown(() => db.close());

  Future<DictionaryMeta> install(
    String name, {
    String? revision,
    String? indexUrl,
    List<String> glossaries = const ['gloss'],
  }) async {
    final id = await repo.insertDictionary(
      name,
      revision: revision,
      indexUrl: indexUrl,
    );
    await repo.batchInsertEntries([
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(glossaries),
        dictionaryId: id,
      ),
    ]);
    return (await repo.getAllDictionaries()).firstWhere((d) => d.id == id);
  }

  DictionaryUpdateService serviceAnswering(Map<String, Object?> index) =>
      DictionaryUpdateService(
        repo,
        client: MockClient(
          (request) async => http.Response(jsonEncode(index), 200),
        ),
      );

  group('where a dictionary publishes its updates', () {
    final service = DictionaryUpdateService.new;

    test('the index URL stored at import wins', () async {
      final meta = await install(
        'Jitendex.org [2026-09-01]',
        indexUrl: 'https://example.com/index.json',
      );
      expect(
        await service(repo).indexUrlFor(meta),
        'https://example.com/index.json',
      );
    });

    test('catalog dictionaries use the catalog index', () async {
      final meta = await install('Jitendex.org [2026-09-01]');
      expect(
        await service(repo).indexUrlFor(meta),
        CatalogDictionary.jitendex.indexUrl,
      );
    });

    test('English JMdict with examples is told apart by its entries', () async {
      final withExamples = await install(
        'JMdict [2026-09-01]',
        glossaries: [
          jsonEncode({
            'type': 'structured-content',
            'content': {
              'tag': 'div',
              'data': {'content': 'examples'},
              'content': 'これは例です。',
            },
          }),
        ],
      );
      final plain = await install('JMdict [2026-09-01]');

      expect(
        await service(repo).indexUrlFor(withExamples),
        '$jmdictYomitanReleases/JMdict_english_with_examples.json',
      );
      expect(
        await service(repo).indexUrlFor(plain),
        '$jmdictYomitanReleases/JMdict_english.json',
      );
    });

    test(
      'the worked-out JMdict index is saved, so it is probed once',
      () async {
        final meta = await install('JMdict [2026-09-01]');
        await service(repo).indexUrlFor(meta);

        final saved = (await repo.getAllDictionaries()).single;
        expect(saved.indexUrl, '$jmdictYomitanReleases/JMdict_english.json');
      },
    );

    test('English KANJIDIC uses its release index', () async {
      final meta = await install('KANJIDIC [2026-276]');
      expect(
        await service(repo).indexUrlFor(meta),
        '$jmdictYomitanReleases/KANJIDIC_english.json',
      );
    });

    test('other dictionaries publish nothing', () async {
      expect(await service(repo).indexUrlFor(await install('JPDBv2㋕')), isNull);
      expect(
        await service(repo).indexUrlFor(await install('My Dictionary')),
        isNull,
      );
    });
  });

  group('checking for an update', () {
    test('a different published revision is an update', () async {
      final meta = await install(
        'Jitendex.org [2026-09-01]',
        revision: '2026.09.01.0',
      );
      final update = await serviceAnswering({
        'title': 'Jitendex.org [2026-10-03]',
        'revision': '2026.10.03.0',
        'downloadUrl': 'https://example.com/jitendex.zip',
      }).checkForUpdate(meta);

      expect(update?.downloadUrl, 'https://example.com/jitendex.zip');
    });

    test('the same revision is no update', () async {
      final meta = await install('wty-ja-en', revision: '2026.10.02');
      final update = await serviceAnswering({
        'title': 'wty-ja-en',
        'revision': '2026.10.02',
        'downloadUrl': 'https://example.com/wty-ja-en.zip',
      }).checkForUpdate(meta);

      expect(update, isNull);
    });

    test('without a stored revision, a newer title is an update', () async {
      final meta = await install('JMdict [2026-09-01]');
      final update = await serviceAnswering({
        'title': 'JMdict [2026-10-03]',
        'revision': 'JMdict.2026-10-03',
        'downloadUrl': 'https://example.com/JMdict_english.zip',
      }).checkForUpdate(meta);

      expect(update?.downloadUrl, 'https://example.com/JMdict_english.zip');
    });

    test('an older published revision is no update', () async {
      final meta = await install('wty-ja-en', revision: '2026.10.02');
      final update = await serviceAnswering({
        'title': 'wty-ja-en',
        'revision': '2026.9.30',
        'downloadUrl': 'https://example.com/wty-ja-en.zip',
      }).checkForUpdate(meta);

      expect(update, isNull);
    });

    test('a stored index URL that is not a URL gives no update', () async {
      final meta = await install('Custom', indexUrl: 'not a url');
      expect(await DictionaryUpdateService(repo).checkForUpdate(meta), isNull);
    });

    test('an index that is unreachable or not https gives no update', () async {
      final meta = await install('Jitendex.org [2026-09-01]');
      final failing = DictionaryUpdateService(
        repo,
        client: MockClient((request) async => http.Response('', 503)),
      );
      expect(await failing.checkForUpdate(meta), isNull);

      final insecure = await serviceAnswering({
        'title': 'Jitendex.org [2026-10-03]',
        'downloadUrl': 'http://example.com/jitendex.zip',
      }).checkForUpdate(meta);
      expect(insecure, isNull);
    });
  });

  test('revisions compare by their numbers, then their text', () {
    expect(isNewerRevision('2026.10.03.0', '2026.9.30.0'), isTrue);
    expect(isNewerRevision('JMdict.2026-10-03', 'JMdict.2026-09-01'), isTrue);
    expect(isNewerRevision('kanjidic2.2026-276', 'kanjidic2.2026-99'), isTrue);
    expect(isNewerRevision('2026.10.02', '2026.10.02'), isFalse);
    expect(
      isNewerRevision('JMdict [2026-09-01]', 'JMdict [2026-10-03]'),
      isFalse,
    );
  });

  group('swapping in a new revision', () {
    test(
      "it takes the old one's current state, then the old one goes",
      () async {
        final old = await install('JMnedict [2026-09-01]');
        final fresh = await install('JMnedict [2026-10-03]');
        // Changed while the update downloaded.
        await repo.toggleDictionary(old.id, isEnabled: false);

        await repo.replaceDictionary(old.id, fresh.id);

        final left = (await repo.getAllDictionaries()).single;
        expect(left.id, fresh.id);
        expect(left.isEnabled, isFalse);
      },
    );

    test(
      'when the old one was deleted meanwhile, the new one goes too',
      () async {
        final old = await install('JMnedict [2026-09-01]');
        final fresh = await install('JMnedict [2026-10-03]');
        await repo.deleteDictionary(old.id);

        await repo.replaceDictionary(old.id, fresh.id);

        expect(await repo.getAllDictionaries(), isEmpty);
      },
    );
  });

  test('an update that stopped before the swap finishes without '
      'downloading again', () async {
    final old = await install('JMnedict [2026-09-01]');
    await install('JMnedict [2026-10-03]', revision: 'JMnedict.2026-10-03');

    await DictionaryUpdateService(repo).apply(
      old,
      const DictionaryUpdate(
        downloadUrl: 'https://127.0.0.1:1/never.zip',
        indexUrl: '$jmdictYomitanReleases/JMnedict.json',
        revision: 'JMnedict.2026-10-03',
      ),
      importer: DictionaryImporter(repo),
    );

    final left = (await repo.getAllDictionaries()).single;
    expect(left.name, 'JMnedict [2026-10-03]');
  });

  group('applying an update', () {
    late Directory tempDir;
    late HttpServer server;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('dictionary_update_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
      final index = utf8.encode(
        jsonEncode({
          'title': 'JMnedict [2026-10-03]',
          'format': 3,
          'revision': 'JMnedict.2026-10-03',
          'isUpdatable': true,
          'indexUrl': '$jmdictYomitanReleases/JMnedict.json',
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
      server.listen((request) async {
        request.response
          ..contentLength = zip.length
          ..add(zip);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tempDir.deleteSync(recursive: true);
    });

    test(
      'the new revision takes the old one\'s place, state and order',
      () async {
        await install('Jitendex.org [2026-10-03]');
        final old = await install('JMnedict [2026-09-01]');
        await repo.toggleDictionary(old.id, isEnabled: false);
        await repo.reorderDictionaries([old.id, 1]);
        final before = (await repo.getAllDictionaries()).firstWhere(
          (d) => d.id == old.id,
        );
        final progress = <double>[];

        await DictionaryUpdateService(repo).apply(
          before,
          DictionaryUpdate(
            downloadUrl: 'http://127.0.0.1:${server.port}/JMnedict.zip',
            indexUrl: '$jmdictYomitanReleases/JMnedict.json',
            revision: 'JMnedict.2026-10-03',
          ),
          importer: DictionaryImporter(repo),
          onProgress: progress.add,
        );

        final dictionaries = await repo.getAllDictionaries();
        expect(dictionaries.map((d) => d.name), [
          'JMnedict [2026-10-03]',
          'Jitendex.org [2026-10-03]',
        ]);
        final updated = dictionaries.first;
        expect(updated.isEnabled, isFalse);
        expect(updated.sortOrder, before.sortOrder);
        expect(updated.revision, 'JMnedict.2026-10-03');
        expect(progress.last, 1.0);
        expect(await repo.getTotalEntryCount(), 2);
      },
    );

    test('on iOS the swap still runs as background work', () async {
      // Leaving the app during a long swap must not suspend it halfway.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('mekuru/background_work');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final events = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'update') events.add(call.method);
        return call.method == 'begin' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final swapping = _SwapRecordingRepository(db, events);
      final old = await install('JMnedict [2026-09-01]');

      await DictionaryUpdateService(swapping).apply(
        old,
        DictionaryUpdate(
          downloadUrl: 'http://127.0.0.1:${server.port}/JMnedict.zip',
          indexUrl: '$jmdictYomitanReleases/JMnedict.json',
          revision: 'JMnedict.2026-10-03',
        ),
        importer: DictionaryImporter(swapping),
      );

      expect(events, ['begin', 'swap', 'end']);
    });
  });
}

class _SwapRecordingRepository extends DictionaryRepository {
  _SwapRecordingRepository(super.db, this.events);

  final List<String> events;

  @override
  Future<void> replaceDictionary(int oldId, int replacementId) {
    events.add('swap');
    return super.replaceDictionary(oldId, replacementId);
  }
}
