import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';

/// Real Android service, plugin, cache and journal; only inference is synthetic.
/// The synthetic engine is compiled exclusively into the plugin's debug build.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File cache;
  late int bookId;
  Future<OcrJobProgress> waitFor(
    String id,
    bool Function(OcrJobProgress) predicate,
  ) async {
    final until = DateTime.now().add(const Duration(seconds: 45));
    OcrJobProgress? last;
    while (DateTime.now().isBefore(until)) {
      // A finished job may be deleted between polls; keep the last snapshot.
      last = (await LocalMangaOcr.jobs()).where((j) => j.id == id).firstOrNull;
      if (last != null && predicate(last)) return last;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('OCR did not reach expected state: ${last?.json}');
  }

  Future<OcrJobProgress> start({
    List<int> pages = const [0, 1, 2, 3],
    bool replace = false,
    int delay = 12,
    int blank = -1,
    int fail = -1,
  }) async {
    final result = await LocalMangaOcr.channel
        .invokeMapMethod<String, dynamic>('start', {
          'bookId': bookId,
          'title': 'OCR integration test',
          'cachePath': cache.path,
          'pages': pages,
          'replace': replace,
          'testEngine': true,
          'testDelaySteps': delay,
          'testBlankPage': blank,
          'testFailPage': fail,
        });
    return OcrJobProgress(result!);
  }

  Future<Map<String, dynamic>> readCache() async =>
      jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
  setUp(() async {
    root = await Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'ocr_it_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create();
    bookId = DateTime.now().millisecondsSinceEpoch % 2000000000;
    cache = File(p.join(root.path, 'pages_cache.json'));
    await cache.writeAsString(
      jsonEncode({
        'title': 'OCR integration test',
        'imageDirPath': root.path,
        'ocrCompleted': false,
        'pages': [
          for (var i = 0; i < 4; i++)
            {
              'pageIndex': i,
              'imageFileName': '$i.png',
              'imgWidth': 100,
              'imgHeight': 120,
              'blocks': <Object>[],
            },
        ],
      }),
    );
  });
  tearDown(() async {
    await LocalMangaOcr.channel.invokeMethod('cancelBook', {'bookId': bookId});
    await LocalMangaOcr.quiesce();
    if (await root.exists()) await root.delete(recursive: true);
  });
  testWidgets('single-page job commits only the selected page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('OCR integration'))),
    );
    final job = await start(pages: [2]);
    final result = await waitFor(job.id, (j) => !j.isActive);
    expect(result.status, 'completed');
    final pages = (await readCache())['pages'] as List;
    expect((pages[2]['blocks'] as List), isNotEmpty);
    expect(pages[0]['blocks'], isEmpty);
    expect(pages[1]['blocks'], isEmpty);
    expect(pages[3]['blocks'], isEmpty);
  });
  testWidgets('word targets merge while remaining pages continue scanning', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final job = await start(delay: 30);
    await waitFor(job.id, (j) => j.succeeded >= 1);
    final before = await cache.readAsString();
    final manga = MokuroBook.fromJson(
      jsonDecode(before) as Map<String, dynamic>,
    );
    final segmented = await MokuroWordSegmenter.segmentBookInBackground(
      manga,
      onlyStale: true,
    );
    expect(segmented.cacheJson, isNotNull);
    await MangaCacheStore.merge(
      cache,
      before: before,
      after: segmented.cacheJson!,
    );
    await waitFor(job.id, (j) => !j.isActive);
    final current = MokuroBook.fromJson(await readCache());
    expect(current.ocrCompleted, true);
    final words = current.pages.first.blocks.first.words;
    expect(words, isNotEmpty);
    expect(
      words.map((w) => w.surface).join(),
      current.pages.first.blocks.first.lines.join(),
    );
    for (final word in words) {
      expect(word.boundingBox.left, greaterThanOrEqualTo(10));
      expect(word.boundingBox.right, lessThanOrEqualTo(40));
      expect(word.boundingBox.top, greaterThanOrEqualTo(10));
      expect(word.boundingBox.bottom, lessThanOrEqualTo(100));
    }
    expect(current.pages.first.ocr?['revision'], 1);
    expect(current.pages.every((p) => p.hasOcr(current)), true);
  });
  testWidgets(
    'pause and resume preserve partial results and successful blanks',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final job = await start(delay: 30, blank: 0);
      await waitFor(job.id, (j) => j.succeeded >= 1);
      await LocalMangaOcr.pause(job.id);
      final paused = await waitFor(job.id, (j) => j.status == 'paused');
      expect(paused.succeeded, lessThan(4));
      final before = await readCache();
      expect(before['pages'][0]['ocr']['completed'], true);
      expect(before['pages'][0]['blocks'], isEmpty);
      await LocalMangaOcr.resume(job.id);
      final done = await waitFor(job.id, (j) => !j.isActive);
      expect(done.status, 'completed');
      final after = await readCache();
      expect(
        after['pages'][0]['ocr']['revision'],
        before['pages'][0]['ocr']['revision'],
      );
      expect(after['ocrCompleted'], true);
    },
  );
  testWidgets(
    'cancelled replacement preserves earlier OCR and rejects late commits',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final initial = await start();
      await waitFor(initial.id, (j) => !j.isActive);
      final before = await readCache();
      final replacement = await start(replace: true, delay: 100);
      await waitFor(replacement.id, (j) => j.status == 'running');
      await LocalMangaOcr.cancel(replacement.id);
      await waitFor(replacement.id, (j) => j.status == 'cancelled');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect((await readCache())['pages'], before['pages']);
    },
  );
  testWidgets('native writer excludes a simultaneous remote job', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final job = await start(delay: 100);
    await expectLater(
      LocalMangaOcr.channel.invokeMethod('claimRemote', {
        'bookId': bookId,
        'title': 'Remote',
        'cachePath': cache.path,
        'pages': [0],
        'replace': true,
      }),
      throwsA(anything),
    );
    await LocalMangaOcr.cancel(job.id);
    await waitFor(job.id, (j) => !j.isActive);
  });
  testWidgets('page errors stay retryable and do not mark book complete', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final job = await start(fail: 1);
    final done = await waitFor(job.id, (j) => !j.isActive);
    expect(done.status, 'completedWithErrors');
    expect(done.failed, 1);
    expect(done.succeeded, 3);
    expect((await readCache())['ocrCompleted'], false);
  });
  testWidgets('deleting a cache during OCR cannot recreate it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final job = await start(delay: 100);
    await waitFor(job.id, (j) => j.status == 'running');
    await LocalMangaOcr.channel.invokeMethod('cancelBook', {'bookId': bookId});
    await cache.delete();
    await LocalMangaOcr.quiesce();
    expect(await cache.exists(), false);
  });
}
