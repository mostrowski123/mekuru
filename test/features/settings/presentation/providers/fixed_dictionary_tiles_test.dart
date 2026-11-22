import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart'
    show DictionaryParseException;
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/jmdict_download_tile.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/downloads/download.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/free_space_fakes.dart';
import '../../../../shared/loopback_http.dart';
import '../../../../shared/test_database.dart';

/// What a fixed-dictionary tile on the Downloads screen shows. [progress] is
/// null while no download runs, since the bar is hidden then.
typedef _Shown = ({
  bool installed,
  bool downloading,
  bool deleting,
  double? progress,
  TileOutcome? outcome,
});

/// One of the three fixed-dictionary tiles (JMdict English, KANJIDIC English,
/// JPDB frequency). The tests below run unchanged against each; only this
/// table knows which notifier backs a tile.
class _Tile {
  const _Tile({
    required this.dictionary,
    required this.home,
    required this.name,
    required this.url,
    required this.title,
    required this.watch,
    required this.checkStatus,
    required this.download,
    required this.delete,
    required this.room,
  });

  final FixedDictionary dictionary;

  /// The screen the tile is on.
  final Widget home;

  final String name;

  /// The free bytes a download asks for.
  final int room;

  /// What a download fetches, as `host/path`.
  final String url;

  /// The dictionary's title in its zip, which the app stores as its name.
  final String title;

  /// The tile now, and each change from here on to [onChange].
  final _Shown Function(ProviderContainer c, [void Function(_Shown)? onChange])
  watch;
  final Future<void> Function(ProviderContainer c) checkStatus;
  final Future<void> Function(ProviderContainer c) download;
  final Future<void> Function(ProviderContainer c) delete;
}

_Shown _view(DownloadTileState s) => (
  installed: s.isInstalled,
  downloading: s.isDownloading,
  deleting: s.isDeleting,
  progress: s.isDownloading ? s.progress : null,
  outcome: s.outcome,
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
    dictionary: FixedDictionary.jmdict,
    home: const Scaffold(body: JmdictDownloadTile()),
    name: 'JMdict',
    url:
        'github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
        'JMdict_english.zip',
    title: 'JMdict (English) [2026-11-01]',
    watch: _watch(_jmdict, _view),
    checkStatus: (c) => c.read(_jmdict.notifier).checkStatus(),
    download: (c) => c
        .read(_jmdict.notifier)
        .download(_unwatched, YomitanDictType.jmdictEnglish),
    delete: (c) => c.read(_jmdict.notifier).delete(),
    // 15.6 MB zip + 2 × 281.4 MB of database.
    room: 578_400_000,
  ),
  _Tile(
    dictionary: FixedDictionary.kanjidic,
    home: const DownloadsScreen(),
    name: 'KANJIDIC',
    url:
        'github.com/yomidevs/jmdict-yomitan/releases/latest/download/'
        'KANJIDIC_english.zip',
    title: 'KANJIDIC (English) [2026-11-01]',
    watch: _watch(_kanjidic, _view),
    checkStatus: (c) => c.read(_kanjidic.notifier).checkStatus(),
    download: (c) => c.read(_kanjidic.notifier).download(_unwatched),
    delete: (c) => c.read(_kanjidic.notifier).delete(),
    // 0.7 MB zip + 2 × 2.7 MB of database.
    room: 6_100_000,
  ),
  _Tile(
    dictionary: FixedDictionary.jpdb,
    home: const DownloadsScreen(),
    name: 'JPDB',
    url:
        'github.com/Kuuuube/yomitan-dictionaries/raw/main/dictionaries/'
        'JPDB_v2.2_Frequency_Kana_2024-10-13.zip',
    title: 'JPDBv2㋕',
    watch: _watch(_jpdb, _view),
    checkStatus: (c) => c.read(_jpdb.notifier).checkStatus(),
    download: (c) => c.read(_jpdb.notifier).download(_unwatched),
    delete: (c) => c.read(_jpdb.notifier).delete(),
    // 6.0 MB zip + 2 × 39.1 MB of database.
    room: 84_200_000,
  ),
];

/// The real notifier without the status check its tile runs when it opens,
/// which would clear the tile's message when it ends.
class _NoStatusCheck extends FixedDictionaryNotifier {
  _NoStatusCheck(super.dictionary);

  @override
  Future<void> checkStatus() async {}
}

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
  outcome: null,
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

  /// A tile whose download failed with an error [matching].
  void expectFailed(_Shown shown, Matcher matching) {
    expect(
      (shown.installed, shown.downloading, shown.deleting, shown.progress),
      (false, false, false, null),
    );
    expect(shown.outcome?.action, TileAction.download);
    expect(shown.outcome?.error, matching);
  }

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
          outcome: null,
        ));
        final progress = [for (final s in seen) ?s.progress];
        expect(progress, orderedEquals([...progress]..sort()));
        expect(progress.last, 1.0);
        expect(seen.last, (
          installed: true,
          downloading: false,
          deleting: false,
          progress: null,
          outcome: (action: TileAction.download, error: null),
        ));
        expect(await names(), [tile.title]);
        expect(tempDir.listSync().whereType<File>(), isEmpty);
      });

      test('a failed download shows why and installs nothing', () async {
        final seen = <_Shown>[];
        tile.watch(container, seen.add);

        await tile.download(container);

        expect(seen.first.downloading, isTrue);
        expectFailed(
          seen.last,
          isA<DownloadHttpException>().having(
            (e) => e.statusCode,
            'status',
            404,
          ),
        );
        expect(await names(), isEmpty);
        expect(tempDir.listSync().whereType<File>(), isEmpty);
      });

      test('an error page in place of the zip installs nothing', () async {
        // Was: "Download complete." and an empty "Unknown Dictionary".
        http.handler = serve('<html><body>Sign in</body></html>'.codeUnits);

        await tile.download(container);

        expectFailed(tile.watch(container), isA<DictionaryParseException>());
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
          outcome: (action: TileAction.download, error: null),
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
        expect(seen.last, (
          installed: false,
          downloading: false,
          deleting: false,
          progress: null,
          outcome: (action: TileAction.delete, error: null),
        ));
        expect(await names(), ['Jitendex.org [2026-11-01]']);
      });

      test('without room for the dictionary it fetches nothing and says how '
          'much more it needs', () async {
        mockFreeBytes(1000);
        http.handler = serve(_zip(tile.title));

        await tile.download(container);

        expect(http.requests, isEmpty);
        expectFailed(
          tile.watch(container),
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'needed',
            tile.room - 1000,
          ),
        );
        expect(await names(), isEmpty);
        expect(tempDir.listSync(recursive: true), isEmpty);
      });

      testWidgets('in Japanese, its tile says why a download failed, then '
          'that it downloaded, then that it was deleted', (tester) async {
        final ja = lookupAppLocalizations(const Locale('ja'));
        final screen = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ...fakeDownloadNotifierOverrides(
              [],
              fixed: (d) => d == tile.dictionary ? _NoStatusCheck(d) : null,
            ),
          ],
        );
        addTearDown(screen.dispose);
        await pumpInJapanese(tester, screen, home: tile.home);
        Future<void> shows(Future<void> Function() action, String text) async {
          await tester.runAsync(action);
          await tester.pump();
          expect(find.text(text), findsOneWidget);
          expect(untranslatedDownloadText, findsNothing);
        }

        await shows(
          () => tile.download(screen),
          ja.serverBrowseDownloadFailed(
            reason: ja.serverErrorStatus(status: 404),
          ),
        );
        http.handler = serve(_zip(tile.title));
        await shows(() => tile.download(screen), ja.downloadsDownloadComplete);
        await shows(() => tile.delete(screen), ja.downloadsDeleted);
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
    expect(container.read(_jmdict).isInstalled, isTrue);
  });
}
