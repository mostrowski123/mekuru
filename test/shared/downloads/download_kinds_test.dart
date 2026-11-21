import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_ios.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/data/services/kanjivg_download_service.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio_pack.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fake_download_notifiers.dart' show mockWifiConnected;
import '../fake_path_provider.dart';
import '../loopback_http.dart';
import '../test_database.dart';

/// What each download kind does around its transfer, through the kind's own
/// entry point, against a loopback server: whether it checks for room, where
/// its file lives while it arrives, whether a transfer cut off keeps its file
/// and the next one resumes it, whether iOS runs it as background work, and
/// whether it stops when Wi-Fi drops. The gaps are pinned as they are; a fix
/// changes its kind's row here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LoopbackHttp http;
  // The app's directories are [root]; Android's no_backup sits next to it.
  late Directory base;
  late String root;
  late AppDatabase db;
  late List<String> backgroundCalls;
  late Completer<void> gate;
  int? free;

  /// Promises [length] bytes, sends 1000, and holds the rest back until
  /// [gate] opens, then drops the connection.
  LoopbackHandler held(int length) => (request) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.add(
      ascii.encode('HTTP/1.1 200 OK\r\ncontent-length: $length\r\n\r\n'),
    );
    socket.add(List.filled(1000, 7));
    await socket.flush();
    await gate.future;
    socket.destroy();
  };

  /// Every file under [base], `/`-separated, with its length.
  Map<String, int> files() => {
    for (final f in base.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: base.path).replaceAll(r'\', '/'): f.lengthSync(),
  };

  DictionaryImporter importer() => DictionaryImporter(DictionaryRepository(db));

  const smallFile = (
    name: 'word_audio_test.sqlite',
    url: 'https://example.org/word_audio_test.sqlite',
    bytes: 4000,
    sha256: '0000000000000000000000000000000000000000000000000000000000000000',
  );

  // Each kind's entry point, the bytes its server promises, the path its
  // file has while it arrives, and the rules it has today.
  final kinds =
      <
        ({
          String name,
          Future<void> Function(NetworkConsent network) start,
          int length,
          String arriving,
          bool room,
          bool resume,
          bool iosWork,
          bool androidToo,
        })
      >[
        (
          name: 'catalog dictionary',
          start: (network) => DictionaryDownloadService.downloadAndImportUrl(
            kind: DownloadKind.catalogDictionary,
            url: 'https://example.org/dictionaries/Jitendex.zip',
            asset: 'jitendex',
            importer: importer(),
            network: network,
            requiredBytes: 5000,
          ),
          length: 4000,
          arriving: r'^app/download_\d+_Jitendex\.zip$',
          room: true,
          resume: false,
          iosWork: true,
          androidToo: true,
        ),
        (
          name: 'JMdict English tile',
          start: (network) => YomitanDictDownloadService.downloadAndImport(
            type: YomitanDictType.jmdictEnglish,
            repository: DictionaryRepository(db),
            importer: importer(),
            network: network,
          ),
          length: 4000,
          arriving: r'^app/download_\d+_JMdict_english\.zip$',
          room: false,
          resume: false,
          iosWork: true,
          androidToo: true,
        ),
        (
          name: 'JPDB tile',
          start: (network) => JpdbFreqDownloadService.downloadAndImport(
            repository: DictionaryRepository(db),
            importer: importer(),
            network: network,
          ),
          length: 4000,
          arriving:
              r'^app/download_\d+_JPDB_v2\.2_Frequency_Kana_2024-10-13\.zip$',
          room: false,
          resume: false,
          iosWork: true,
          androidToo: true,
        ),
        (
          name: 'KanjiVG',
          start: (network) =>
              KanjiVgDownloadService.downloadAndExtract(network: network),
          length: 4000,
          arriving: r'^app/kanjivg_download\.zip$',
          room: false,
          resume: false,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'UniDic-lite',
          start: (network) =>
              EnhancedFuriganaDictDownloadService.downloadAndInstall(
                network: network,
              ),
          length: 4000,
          arriving: r'^app/unidic_lite_download\.tar\.gz$',
          room: false,
          resume: false,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'manga-ocr pack (iOS)',
          start: (network) => MangaOcrIos.instance.download(network: network),
          length: mangaOcrIosModelFiles.first.bytes,
          arriving: r'^app/manga_ocr_models/encoder_model_fp16\.onnx\.part$',
          room: false,
          resume: true,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'NDL text model',
          start: (network) => NdlTextModel.instance.download(network: network),
          length: ndlTextModelFiles.first.bytes,
          arriving:
              r'^(no_backup|app)/ndl_text_model/'
              r'parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604'
              r'\.onnx\.part$',
          room: false,
          resume: true,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'Standard translation model',
          start: (network) =>
              MozillaTranslation.instance.download('en', network),
          length: mozillaTranslationModels['ja-en']!.first.bytes,
          arriving:
              '^app/translation_models/ja-en/'
              '${RegExp.escape(mozillaTranslationModels['ja-en']!.first.name)}'
              r'\.part$',
          room: false,
          resume: true,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'word audio list',
          start: (network) =>
              WordAudio(indexFile: smallFile).download(network: network),
          length: smallFile.bytes,
          arriving:
              r'^(no_backup|app)/word_audio/word_audio_test\.sqlite\.part$',
          room: false,
          resume: true,
          iosWork: false,
          androidToo: true,
        ),
        (
          name: 'word audio pack (iOS)',
          start: (network) =>
              WordAudioPack(file: smallFile).download(network: network),
          length: smallFile.bytes,
          arriving: r'^app/word_audio_pack/word_audio_test\.sqlite\.part$',
          room: true,
          resume: true,
          iosWork: true,
          // On Android the pack is a WorkManager job (ModelDownloadJob).
          androidToo: false,
        ),
      ];

  setUpAll(() async {
    base = Directory.systemTemp.createTempSync('download_kinds_');
    root = p.join(base.path, 'app');
    // Once for the file: the Standard translation engine keeps the first app
    // directory it sees.
    PathProviderPlatform.instance = FakePathProviderPlatform(root);
    http = await LoopbackHttp.start();
  });

  tearDownAll(() async {
    await http.close();
    base.deleteSync(recursive: true);
  });

  setUp(() {
    http.reset();
    for (final entity in base.listSync()) {
      entity.deleteSync(recursive: true);
    }
    Directory(root).createSync();
    db = createTestDatabase();
    gate = Completer<void>();
    free = 1;
    backgroundCalls = [];
    mockWifiConnected(true);
    messenger.setMockMethodCallHandler(
      const MethodChannel('mekuru/android_saf'),
      (call) async => call.method == 'getFreeBytes' ? free : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mekuru/ios_files'),
      (call) async => call.method == 'freeBytes' ? free : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mekuru/background_work'),
      (call) async {
        backgroundCalls.add(call.method);
        return call.method == 'begin' ? true : null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('mekuru/ios_storage'),
      (_) async => null,
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (!gate.isCompleted) gate.complete();
    for (final name in [
      'mekuru/android_saf',
      'mekuru/ios_files',
      'mekuru/background_work',
      'mekuru/ios_storage',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    await db.close();
  });

  /// The file under [base] that holds the 1000 bytes sent so far, or null
  /// once [download] has ended without one.
  Future<String?> arriving(Future<void> download) async {
    var ended = false;
    unawaited(download.then((_) => ended = true, onError: (_) => ended = true));
    for (var i = 0; i < 500; i++) {
      for (final MapEntry(:key, :value) in files().entries) {
        if (value == 1000) return key;
      }
      if (ended) return null;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('nothing arrived');
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final kind in kinds) {
      if (platform == TargetPlatform.android && !kind.androidToo) continue;
      test(
        '${kind.name} on ${platform.name}: room '
        '${kind.room ? 'checked' : 'not checked'}, '
        '${kind.resume ? 'resumed' : 'not resumed'}, '
        '${kind.iosWork ? 'background work on iOS' : 'no background work'}',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          http.handler = held(kind.length);
          // One byte free: a kind that checks stops before any request.
          if (kind.room) {
            await expectLater(
              kind.start(NetworkConsent.mobileData),
              throwsA(isA<InsufficientSpaceException>()),
            );
            expect(http.requests, isEmpty);
            free = null;
          }
          final first = kind.start(NetworkConsent.mobileData);
          final failed = expectLater(first, throwsA(anything));

          final path = await arriving(first);

          expect(path, matches(kind.arriving));
          expect(
            backgroundCalls.contains('begin'),
            kind.iosWork && platform == TargetPlatform.iOS,
          );
          gate.complete();
          await failed;
          // A transfer cut off keeps its file only when the next one resumes.
          expect(files().containsKey(path), kind.resume);

          http.handler = notFound;
          await expectLater(
            kind.start(NetworkConsent.mobileData),
            throwsA(anything),
          );
          expect(http.ranges.last, kind.resume ? 'bytes=1000-' : isNull);
        },
      );
    }
  }

  test('a model reports each whole percent of its bytes once, from the first '
      'bytes to 1.0', () async {
    // Many socket chunks, so most arrive within a percent of the last.
    final body = Uint8List(16 << 20);
    final file = (
      name: 'word_audio_test.sqlite',
      url: 'https://example.org/word_audio_test.sqlite',
      bytes: body.length,
      sha256: sha256.convert(body).toString(),
    );
    http.handler = serve(body);
    final seen = <double>[];

    final audio = WordAudio(indexFile: file);
    await audio.download(
      network: NetworkConsent.mobileData,
      onProgress: seen.add,
    );

    expect(await audio.installed, isTrue);
    expect(seen.first, greaterThan(0));
    expect(seen.last, 1.0);
    expect(seen.length, lessThanOrEqualTo(101));
    expect(seen, orderedEquals(seen.toSet().toList()..sort()));
  });

  for (final kind in kinds) {
    test('${kind.name}: a download started on Wi-Fi stops when Wi-Fi '
        'drops', () async {
      if (!kind.androidToo) {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      }
      free = null;
      http.handler = held(kind.length);

      final download = kind.start(NetworkConsent.wifiOnly);
      final stopped = expectLater(download, throwsA(isA<WifiLostException>()));
      await arriving(download);
      mockWifiConnected(false);

      await stopped;
    });
  }
}
