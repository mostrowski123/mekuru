import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/loopback_http.dart';
import '../../../../shared/test_database.dart';

/// What a fixed-dictionary tile on the Downloads screen shows. [progress] is
/// null while no download runs, since the bar is hidden then.
typedef _Shown = ({
  bool installed,
  bool downloading,
  bool deleting,
  double? progress,
  String? error,
  String? message,
});

/// One of the three fixed-dictionary tiles (JMdict English, KANJIDIC English,
/// JPDB frequency). The tests below run unchanged against each; only this
/// table knows which notifier backs a tile.
class _Tile {
  const _Tile({
    required this.name,
    required this.url,
    required this.title,
    required this.downloaded,
    required this.deleted,
    required this.watch,
    required this.checkStatus,
    required this.download,
    required this.delete,
  });

  final String name;

  /// What a download fetches, as `host/path`.
  final String url;

  /// The dictionary's title in its zip, which the app stores as its name.
  final String title;
  final String downloaded;
  final String deleted;

  /// The tile now, and each change from here on to [onChange].
  final _Shown Function(ProviderContainer c, [void Function(_Shown)? onChange])
  watch;
  final Future<void> Function(ProviderContainer c) checkStatus;
  final Future<void> Function(ProviderContainer c) download;
  final Future<void> Function(ProviderContainer c) delete;
}

_Shown _shown({
  required bool isImported,
  required bool isDownloading,
  required bool isDeleting,
  required double progress,
  required String? error,
  required String? successMessage,
}) => (
  installed: isImported,
  downloading: isDownloading,
  deleting: isDeleting,
  progress: isDownloading ? progress : null,
  error: error,
  message: successMessage,
);

_Shown _view(FixedDictionaryState s) => _shown(
  isImported: s.isImported,
  isDownloading: s.isDownloading,
  isDeleting: s.isDeleting,
  progress: s.progress,
  error: s.error,
  successMessage: s.successMessage,
);

_Shown Function(ProviderContainer, [void Function(_Shown)?]) _watch<S>(
  NotifierProvider<Notifier<S>, S> provider,
  _Shown Function(S) view,
) => (c, [onChange]) {
  if (onChange != null) {
    c.listen(provider, (_, next) => onChange(view(next)));
  }
  return view(c.read(provider));
};

final _jmdict = fixedDictionaryProvider(FixedDictionary.jmdict);
final _kanjidic = fixedDictionaryProvider(FixedDictionary.kanjidic);

/// No Wi-Fi watch, as these downloads had before the consent was passed in.
const _unwatched = NetworkConsent.mobileData;
final _jpdb = fixedDictionaryProvider(FixedDictionary.jpdb);

final _tiles = [
  _Tile(
    name: 'JMdict',
    url:
        'github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
        'JMdict_english.zip',
    title: 'JMdict (English) [2026-11-01]',
    downloaded: 'JMdict downloaded successfully.',
    deleted: 'JMdict deleted.',
    watch: _watch(_jmdict, _view),
    checkStatus: (c) => c.read(_jmdict.notifier).checkStatus(),
    download: (c) => c
        .read(_jmdict.notifier)
        .download(_unwatched, YomitanDictType.jmdictEnglish),
    delete: (c) => c.read(_jmdict.notifier).delete(),
  ),
  _Tile(
    name: 'KANJIDIC',
    url:
        'github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
        'KANJIDIC_english.zip',
    title: 'KANJIDIC (English) [2026-11-01]',
    downloaded: 'KANJIDIC downloaded successfully.',
    deleted: 'KANJIDIC deleted.',
    watch: _watch(_kanjidic, _view),
    checkStatus: (c) => c.read(_kanjidic.notifier).checkStatus(),
    download: (c) => c.read(_kanjidic.notifier).download(_unwatched),
    delete: (c) => c.read(_kanjidic.notifier).delete(),
  ),
  _Tile(
    name: 'JPDB',
    url:
        'github.com/Kuuuube/yomitan-dictionaries/raw/main/dictionaries/'
        'JPDB_v2.2_Frequency_Kana_2024-10-13.zip',
    title: 'JPDBv2㋕',
    downloaded: 'Frequency dictionary downloaded successfully.',
    deleted: 'Frequency dictionary deleted.',
    watch: _watch(_jpdb, _view),
    checkStatus: (c) => c.read(_jpdb.notifier).checkStatus(),
    download: (c) => c.read(_jpdb.notifier).download(_unwatched),
    delete: (c) => c.read(_jpdb.notifier).delete(),
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

const _idle = (
  installed: false,
  downloading: false,
  deleting: false,
  progress: null,
  error: null,
  message: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LoopbackHttp http;
  late Directory tempDir;
  late AppDatabase db;
  late DictionaryRepository repo;
  late ProviderContainer container;

  setUpAll(() async => http = await LoopbackHttp.start());
  tearDownAll(() => http.close());

  setUp(() {
    http.reset();
    tempDir = Directory.systemTemp.createTempSync('fixed_dictionary_tiles_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<List<String>> names() async => [
    for (final d in await repo.getAllDictionaries()) d.name,
  ];

  for (final tile in _tiles) {
    group('${tile.name} tile', () {
      test('a download shows rising progress, then the dictionary as '
          'installed', () async {
        http.handler = serve(_zip(tile.title));
        final seen = <_Shown>[];
        tile.watch(container, seen.add);

        await tile.download(container);

        expect(http.requests, [tile.url]);
        expect(seen.first, (
          installed: false,
          downloading: true,
          deleting: false,
          progress: 0.0,
          error: null,
          message: null,
        ));
        final progress = [for (final s in seen) ?s.progress];
        expect(progress, orderedEquals([...progress]..sort()));
        expect(progress.last, 1.0);
        // English, not localized: the plan's bug 7 (7e) names only KanjiVG
        // and UniDic, but this text has the same gap.
        expect(seen.last, (
          installed: true,
          downloading: false,
          deleting: false,
          progress: null,
          error: null,
          message: tile.downloaded,
        ));
        expect(await names(), [tile.title]);
        expect(tempDir.listSync().whereType<File>(), isEmpty);
      });

      test('a failed download shows why and installs nothing', () async {
        final seen = <_Shown>[];
        tile.watch(container, seen.add);

        await tile.download(container);

        expect(seen.first.downloading, isTrue);
        expect(seen.last, (
          installed: false,
          downloading: false,
          deleting: false,
          progress: null,
          error: 'Download failed: The server returned error 404.',
          message: null,
        ));
        expect(await names(), isEmpty);
        expect(tempDir.listSync().whereType<File>(), isEmpty);
      });

      test('a second tap while a download runs starts nothing', () async {
        final release = Completer<void>();
        http.handler = (request) async {
          await release.future;
          await serve(_zip(tile.title))(request);
        };

        final first = tile.download(container);
        await tile.download(container);
        expect(tile.watch(container).downloading, isTrue);
        release.complete();
        await first;

        expect(http.requests, hasLength(1));
        expect(await names(), [tile.title]);
      });

      test('an installed dictionary shows as installed, and a download '
          'fetches nothing', () async {
        await tile.checkStatus(container);
        expect(tile.watch(container), _idle);

        await repo.insertDictionary(tile.title);
        await tile.checkStatus(container);
        expect(tile.watch(container).installed, isTrue);

        http.handler = serve(_zip(tile.title));
        await tile.download(container);

        expect(http.requests, isEmpty);
        expect(await names(), [tile.title]);
        // It says "downloaded" although nothing was.
        expect(tile.watch(container), (
          installed: true,
          downloading: false,
          deleting: false,
          progress: null,
          error: null,
          message: tile.downloaded,
        ));
      });

      test('delete removes only this dictionary and says so', () async {
        await repo.insertDictionary('Jitendex.org [2026-11-01]');
        await repo.insertDictionary(tile.title);
        await tile.checkStatus(container);
        final seen = <_Shown>[];
        tile.watch(container, seen.add);

        await tile.delete(container);

        expect(seen.first.deleting, isTrue);
        // English, not localized (same gap as the download message).
        expect(seen.last, (
          installed: false,
          downloading: false,
          deleting: false,
          progress: null,
          error: null,
          message: tile.deleted,
        ));
        expect(await names(), ['Jitendex.org [2026-11-01]']);
      });

      test('a download starts with almost no free space', () async {
        // 7e changes this (bug 3): the tile has no free-space check, so it
        // downloads and imports with 1 KB free.
        const saf = MethodChannel('mekuru/android_saf');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          saf,
          (call) async => call.method == 'getFreeBytes' ? 1000 : null,
        );
        addTearDown(() => messenger.setMockMethodCallHandler(saf, null));
        http.handler = serve(_zip(tile.title));

        await tile.download(container);

        expect(http.requests, [tile.url]);
        expect(tile.watch(container).installed, isTrue);
        expect(await names(), [tile.title]);
      });
    });
  }

  test('the JMdict tile fetches the variant chosen', () async {
    http.handler = serve(_zip('JMdict (English) [2026-11-01]'));

    await container
        .read(_jmdict.notifier)
        .download(_unwatched, YomitanDictType.jmdictEnglishWithExamples);

    expect(http.requests, [
      'github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
          'JMdict_english_with_examples.zip',
    ]);
    expect(container.read(_jmdict).isImported, isTrue);
  });
}
