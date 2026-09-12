import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';
import 'package:mekuru/features/manga/data/services/ocr_page_selection.dart';

MokuroPage page(int index, {Map<String, dynamic>? ocr}) => MokuroPage(
  pageIndex: index,
  imageFileName: '$index.png',
  imgWidth: 100,
  imgHeight: 100,
  blocks: const [],
  ocr: ocr,
);
MokuroBook book(List<MokuroPage> pages, {bool completed = false}) => MokuroBook(
  title: 'Test',
  imageDirPath: '/test',
  pages: pages,
  ocrCompleted: completed,
);

void main() {
  group('page selection and provenance', () {
    test('missing-only skips successful empty pages', () {
      final manga = book([
        page(0, ocr: {'completed': true, 'source': 'onDevice'}),
        page(1),
      ]);
      expect(selectOcrPages(manga), [1]);
    });
    test('replacement explicitly targets completed pages', () {
      final manga = book([page(0), page(1)], completed: true);
      expect(selectOcrPages(manga), isEmpty);
      expect(selectOcrPages(manga, policy: OcrExistingPolicy.replace), [0, 1]);
      expect(
        selectOcrPages(manga, pageIndex: 1, policy: OcrExistingPolicy.replace),
        [1],
      );
    });
    test('invalid page cannot become a whole-book scan', () {
      expect(
        () => selectOcrPages(book([page(0)]), pageIndex: 5),
        throwsRangeError,
      );
      expect(
        () => selectOcrPages(book([page(0)]), pageIndex: -1),
        throwsRangeError,
      );
    });
    test('one-tap targets skip pages with OCR unless replacing', () {
      final manga = book([
        page(0, ocr: {'completed': true, 'source': 'onDevice'}),
        page(1),
        page(2),
      ]);
      expect(quickOcrTargets(manga, [0, 1]), [1]);
      expect(quickOcrTargets(manga, [0, 1], replace: true), [0, 1]);
      expect(quickOcrTargets(manga, [0]), isEmpty);
    });
    test('legacy Mokuro completion includes empty pages', () {
      final manga = MokuroBook.fromJson({
        'title': 'Legacy',
        'imageDirPath': '/test',
        'ocrSource': 'mokuro',
        'pages': [page(0).toJson()],
      });
      expect(selectOcrPages(manga), isEmpty);
    });
    test(
      'page and generation metadata survives cache round trip and copyWith',
      () {
        final json = book([
          page(
            0,
            ocr: {
              'completed': true,
              'source': 'onDevice',
              'modelVersion': 'v1',
              'jobId': 'job',
              'revision': 3,
            },
          ),
        ]).toJson()..['ocrGeneration'] = 'generation';
        final decoded = MokuroBook.fromJson(json).copyWith();
        expect(decoded.toJson()['ocrGeneration'], 'generation');
        expect(
          decoded.pages.single.copyWith().toJson()['ocr'],
          (json['pages'] as List)[0]['ocr'],
        );
      },
    );
    test('failed replacement does not remove previous coverage', () {
      final manga = book([
        page(0, ocr: {'completed': true, 'source': 'remote'}),
      ]);
      final job = OcrJobProgress({
        'id': 'x',
        'bookId': 1,
        'status': 'completedWithErrors',
        'pages': [0],
        'outcomes': {'0': 'failed'},
      });
      expect(job.failed, 1);
      expect(selectOcrPages(manga), isEmpty);
    });
  });
  group('truthful job progress', () {
    test('ETA requires three timed pages and an actively running job', () {
      final data = <String, dynamic>{
        'status': 'running',
        'pages': List.generate(10, (i) => i),
        'outcomes': {'0': 'done', '1': 'done', '2': 'done'},
        'avgPageMs': 4000,
        'timedPages': 2,
      };
      expect(OcrJobProgress(data).etaSeconds, isNull);
      data['timedPages'] = 3;
      expect(OcrJobProgress(data).etaSeconds, 28);
      data['status'] = 'paused';
      expect(OcrJobProgress(data).etaSeconds, isNull);
    });
    test('failed and skipped pages are not reported as saved', () {
      final job = OcrJobProgress({
        'id': 'x',
        'bookId': 1,
        'status': 'completedWithErrors',
        'pages': [0, 1, 2],
        'outcomes': {'0': 'done', '1': 'failed', '2': 'skipped'},
      });
      expect(job.total, 3);
      expect(job.processed, 3);
      expect(job.succeeded, 1);
      expect(job.failed, 1);
      expect(job.skipped, 1);
      expect(job.isActive, false);
      expect(job.canResume, true);
    });
    for (final status in [
      'queued',
      'preparing',
      'running',
      'pausing',
      'cancelling',
    ]) {
      test('$status owns active work', () {
        expect(OcrJobProgress({'status': status}).isActive, true);
      });
    }
    for (final status in ['paused', 'failed', 'completedWithErrors']) {
      test('$status can resume', () {
        expect(OcrJobProgress({'status': status}).canResume, true);
      });
    }
    test('cancelled jobs cannot resume accidentally', () {
      expect(const OcrJobProgress({'status': 'cancelled'}).canResume, false);
    });
    test('spec freezes replacement selection without account fields', () {
      const spec = OcrJobSpec(
        bookId: 1,
        title: 'Test',
        cachePath: '/test',
        pages: [1, 7],
        policy: OcrExistingPolicy.replace,
        onlyWhileCharging: true,
      );
      expect(spec.toJson()['pages'], [1, 7]);
      expect(spec.toJson()['replace'], true);
      expect(spec.toJson().keys, isNot(contains('token')));
      expect(spec.toJson().keys, isNot(contains('credits')));
    });
  });
  group('cache concurrency', () {
    late Map<String, dynamic> before;
    setUp(() {
      before = book([
        page(0, ocr: {'completed': true, 'revision': 1}),
      ]).toJson()..['ocrGeneration'] = 'v1';
    });
    Map<String, dynamic> copy(Map<String, dynamic> input) =>
        jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    test('stale word computation cannot overwrite a new OCR revision', () {
      final current = copy(before);
      current['pages'][0]['ocr']['revision'] = 2;
      final after = copy(before);
      after['pages'][0]['blocks'] = [
        {'old': 'words'},
      ];
      after['pages'][0]['contentBounds'] = [0, 0, 80, 80];
      final merged = MangaCacheStore.mergeJson(current, before, after);
      expect(merged['pages'][0]['blocks'], isEmpty);
      expect(merged['pages'][0]['ocr']['revision'], 2);
      expect(merged['pages'][0]['contentBounds'], [0, 0, 80, 80]);
    });
    test('independent crop and segmentation updates both survive', () {
      before['pages'][0]['blocks'] = [
        {
          'lines': ['test'],
          'words': [],
        },
      ];
      final current = copy(before);
      current['pages'][0]['contentBounds'] = [0, 0, 80, 80];
      final after = copy(before);
      after['pages'][0]['blocks'] = [
        {
          'lines': ['test'],
          'words': [
            {'surface': 'test'},
          ],
        },
      ];
      final merged = MangaCacheStore.mergeJson(current, before, after);
      expect(merged['pages'][0]['blocks'], [
        {
          'lines': ['test'],
          'words': [
            {'surface': 'test'},
          ],
        },
      ]);
      expect(merged['pages'][0]['contentBounds'], [0, 0, 80, 80]);
    });
    test('replacement generation rejects stale async writes', () {
      final current = copy(before)..['ocrGeneration'] = 'v2';
      expect(
        () => MangaCacheStore.mergeJson(current, before, copy(before)),
        throwsStateError,
      );
    });
    test('first native job can add metadata while reader is calculating', () {
      final legacy = copy(before)..remove('ocrGeneration');
      expect(
        MangaCacheStore.mergeJson(before, legacy, legacy)['ocrGeneration'],
        'v1',
      );
    });
    test('page identity changes reject writes', () {
      final current = copy(before);
      current['pages'][0]['imageFileName'] = 'different.png';
      expect(
        () => MangaCacheStore.mergeJson(current, before, copy(before)),
        throwsStateError,
      );
    });
    test('deleted cache is not recreated', () async {
      final root = await Directory.systemTemp.createTemp('ocr-cache-test');
      try {
        final file = File.fromUri(root.uri.resolve('pages_cache.json'));
        await expectLater(
          () => MangaCacheStore.merge(
            file,
            before: jsonEncode(before),
            after: jsonEncode(before),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  test(
    'notification prompt goes through the app bridge, not the plugin',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const bridge = MethodChannel('mekuru/full_backup_job');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            calls.add(call.method);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(bridge, null),
      );
      expect(await const NativeLocalOcrClient().requestNotifications(), isTrue);
      expect(calls, ['requestNotificationPermission']);
    },
  );
}
