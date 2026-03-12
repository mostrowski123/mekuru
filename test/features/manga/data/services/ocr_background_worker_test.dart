import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

class _FakeWorkmanagerPlatform extends WorkmanagerPlatform {
  final List<String> cancelledTags = <String>[];

  @override
  Future<void> cancelByTag(String tag) async {
    cancelledTags.add(tag);
  }
}

void main() {
  group('OcrProgress', () {
    test('toJson and fromJson round-trip', () {
      const progress = OcrProgress(
        completed: 42,
        total: 200,
        status: OcrStatus.running,
        avgSecondsPerPage: 1.5,
      );

      final jsonStr = progress.toJson();
      final restored = OcrProgress.fromJson(jsonStr);

      expect(restored.completed, 42);
      expect(restored.total, 200);
      expect(restored.status, OcrStatus.running);
      expect(restored.avgSecondsPerPage, 1.5);
    });

    test('toJson omits avgSecondsPerPage when null', () {
      const progress = OcrProgress(
        completed: 0,
        total: 10,
        status: OcrStatus.running,
      );

      final data = json.decode(progress.toJson()) as Map<String, dynamic>;
      expect(data.containsKey('avgSecondsPerPage'), isFalse);
    });

    test('fromJson handles missing avgSecondsPerPage', () {
      final jsonStr = json.encode({
        'completed': 5,
        'total': 10,
        'status': 'completed',
      });

      final progress = OcrProgress.fromJson(jsonStr);

      expect(progress.completed, 5);
      expect(progress.total, 10);
      expect(progress.status, OcrStatus.completed);
      expect(progress.avgSecondsPerPage, isNull);
    });

    test('load returns null when no progress stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final progress = OcrProgress.load(prefs, 999);
      expect(progress, isNull);
    });

    test('save and load round-trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const progress = OcrProgress(
        completed: 10,
        total: 50,
        status: OcrStatus.running,
        avgSecondsPerPage: 2.0,
      );

      await OcrProgress.save(prefs, 42, progress);

      final loaded = OcrProgress.load(prefs, 42);
      expect(loaded, isNotNull);
      expect(loaded!.completed, 10);
      expect(loaded.total, 50);
      expect(loaded.status, OcrStatus.running);
      expect(loaded.avgSecondsPerPage, 2.0);
    });

    test('load returns null for invalid JSON', () async {
      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': 'not valid json',
      });
      final prefs = await SharedPreferences.getInstance();

      final progress = OcrProgress.load(prefs, 42);
      expect(progress, isNull);
    });

    test('clear removes progress from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': const OcrProgress(
          completed: 5,
          total: 10,
          status: OcrStatus.running,
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      // Verify it exists
      expect(OcrProgress.load(prefs, 42), isNotNull);

      // Clear it
      await OcrProgress.clear(prefs, 42);

      // Verify it's gone
      expect(OcrProgress.load(prefs, 42), isNull);
    });

    test('different bookIds have independent progress', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await OcrProgress.save(
        prefs,
        1,
        const OcrProgress(completed: 10, total: 100, status: OcrStatus.running),
      );
      await OcrProgress.save(
        prefs,
        2,
        const OcrProgress(
          completed: 50,
          total: 50,
          status: OcrStatus.completed,
        ),
      );

      final p1 = OcrProgress.load(prefs, 1);
      final p2 = OcrProgress.load(prefs, 2);

      expect(p1!.completed, 10);
      expect(p1.status, OcrStatus.running);
      expect(p2!.completed, 50);
      expect(p2.status, OcrStatus.completed);
    });
  });

  group('OcrStatus', () {
    test('status constants have expected values', () {
      expect(OcrStatus.running, 'running');
      expect(OcrStatus.completed, 'completed');
      expect(OcrStatus.cancelled, 'cancelled');
      expect(OcrStatus.failed, 'failed');
      expect(OcrStatus.idle, 'idle');
    });
  });

  group('Constants', () {
    test('ocrTaskName is defined', () {
      expect(ocrTaskName, isNotEmpty);
    });

    test('ocrTaskTagPrefix is defined', () {
      expect(ocrTaskTagPrefix, isNotEmpty);
    });

    test('ocrProgressKeyPrefix is defined', () {
      expect(ocrProgressKeyPrefix, isNotEmpty);
    });

    test('ocrServerUrlKey is defined', () {
      expect(ocrServerUrlKey, isNotEmpty);
    });

    test(
      'defaultOcrServerUrl is empty until a custom server is configured',
      () {
        expect(defaultOcrServerUrl, isEmpty);
      },
    );
  });

  group('stop requests', () {
    late WorkmanagerPlatform originalWorkmanagerPlatform;
    late _FakeWorkmanagerPlatform fakeWorkmanagerPlatform;

    setUp(() {
      originalWorkmanagerPlatform = WorkmanagerPlatform.instance;
      fakeWorkmanagerPlatform = _FakeWorkmanagerPlatform();
      WorkmanagerPlatform.instance = fakeWorkmanagerPlatform;
    });

    tearDown(() {
      WorkmanagerPlatform.instance = originalWorkmanagerPlatform;
    });

    test('cancelOcrTask records a paused stop request', () async {
      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': const OcrProgress(
          completed: 3,
          total: 10,
          status: OcrStatus.running,
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      await cancelOcrTask(42);

      final progress = OcrProgress.load(prefs, 42);
      expect(progress, isNotNull);
      expect(progress!.completed, 3);
      expect(progress.total, 10);
      expect(progress.status, OcrStatus.cancelled);
      expect(await loadOcrStopRequest(42), OcrStopRequest.paused);
      expect(fakeWorkmanagerPlatform.cancelledTags, ['${ocrTaskTagPrefix}42']);
    });

    test(
      'clearOcrTaskState records a delete stop request and hides progress',
      () async {
        SharedPreferences.setMockInitialValues({
          '${ocrProgressKeyPrefix}42': const OcrProgress(
            completed: 3,
            total: 10,
            status: OcrStatus.running,
          ).toJson(),
        });
        final prefs = await SharedPreferences.getInstance();

        await clearOcrTaskState(42);

        final progress = OcrProgress.load(prefs, 42);
        expect(progress, isNotNull);
        expect(progress!.completed, 0);
        expect(progress.total, 0);
        expect(progress.status, OcrStatus.idle);
        expect(await loadOcrStopRequest(42), OcrStopRequest.deleted);
        expect(fakeWorkmanagerPlatform.cancelledTags, [
          '${ocrTaskTagPrefix}42',
        ]);
      },
    );
  });

  group('determineOcrTaskExecutionMode', () {
    test('uses WorkManager when cache file is missing', () async {
      final mode = await determineOcrTaskExecutionMode(
        cacheFilePath: p.join(
          Directory.systemTemp.path,
          'missing_${DateTime.now().microsecondsSinceEpoch}.json',
        ),
      );

      expect(mode, OcrTaskExecutionMode.workmanager);
    });

    test('uses WorkManager for local filesystem manga caches', () async {
      final dir = await Directory.systemTemp.createTemp('ocr_mode_local_');
      addTearDown(() => dir.delete(recursive: true));
      final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
      await cacheFile.writeAsString(
        json.encode({
          'title': 'Local manga',
          'imageDirPath': p.join(dir.path, 'images'),
          'pages': const [],
        }),
      );

      final mode = await determineOcrTaskExecutionMode(
        cacheFilePath: cacheFile.path,
      );

      expect(mode, OcrTaskExecutionMode.workmanager);
    });

    test('uses foreground execution for SAF-backed manga caches', () async {
      final dir = await Directory.systemTemp.createTemp('ocr_mode_saf_');
      addTearDown(() => dir.delete(recursive: true));
      final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
      await cacheFile.writeAsString(
        json.encode({
          'title': 'SAF manga',
          'imageDirPath': '/storage/emulated/0/Manga',
          'safTreeUri': 'content://tree/primary%3AManga',
          'safImageDirRelativePath': 'Series/Volume 1',
          'pages': const [],
        }),
      );

      final mode = await determineOcrTaskExecutionMode(
        cacheFilePath: cacheFile.path,
      );

      expect(mode, OcrTaskExecutionMode.foreground);
    });
  });

  group('buildScheduledOcrProgress', () {
    test('counts only pages that still need OCR blocks', () async {
      final dir = await Directory.systemTemp.createTemp('ocr_schedule_blocks_');
      addTearDown(() => dir.delete(recursive: true));
      final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
      await cacheFile.writeAsString(
        json.encode({
          'title': 'Retry manga',
          'imageDirPath': dir.path,
          'pages': [
            {
              'pageIndex': 0,
              'imageFileName': '0001.jpg',
              'imgWidth': 100,
              'imgHeight': 100,
              'blocks': const [],
            },
            {
              'pageIndex': 1,
              'imageFileName': '0002.jpg',
              'imgWidth': 100,
              'imgHeight': 100,
              'blocks': [
                {
                  'box': [0.0, 0.0, 10.0, 10.0],
                  'vertical': true,
                  'fontSize': 12.0,
                  'linesCoords': const [],
                  'lines': ['text'],
                  'words': const [],
                },
              ],
            },
          ],
        }),
      );

      final progress = await buildScheduledOcrProgress(
        cacheFilePath: cacheFile.path,
      );

      expect(progress.status, OcrStatus.running);
      expect(progress.completed, 1);
      expect(progress.total, 2);
    });

    test(
      'uses pages needing word segmentation when OCR blocks already exist',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'ocr_schedule_words_',
        );
        addTearDown(() => dir.delete(recursive: true));
        final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
        await cacheFile.writeAsString(
          json.encode({
            'title': 'Word overlay pass',
            'imageDirPath': dir.path,
            'pages': [
              {
                'pageIndex': 0,
                'imageFileName': '0001.jpg',
                'imgWidth': 100,
                'imgHeight': 100,
                'blocks': [
                  {
                    'box': [0.0, 0.0, 10.0, 10.0],
                    'vertical': true,
                    'fontSize': 12.0,
                    'linesCoords': const [],
                    'lines': ['text'],
                    'words': const [],
                  },
                ],
              },
              {
                'pageIndex': 1,
                'imageFileName': '0002.jpg',
                'imgWidth': 100,
                'imgHeight': 100,
                'blocks': [
                  {
                    'box': [0.0, 0.0, 10.0, 10.0],
                    'vertical': true,
                    'fontSize': 12.0,
                    'linesCoords': const [],
                    'lines': ['ready'],
                    'words': [
                      {
                        'surface': 'ready',
                        'box': [0.0, 0.0, 5.0, 5.0],
                        'blockIdx': 0,
                        'lineIdx': 0,
                        'charStart': 0,
                        'charEnd': 5,
                      },
                    ],
                  },
                ],
              },
            ],
          }),
        );

        final progress = await buildScheduledOcrProgress(
          cacheFilePath: cacheFile.path,
        );

        expect(progress.status, OcrStatus.running);
        expect(progress.completed, 1);
        expect(progress.total, 2);
      },
    );

    test(
      'falls back to reserved pages when the cache cannot be parsed',
      () async {
        final dir = await Directory.systemTemp.createTemp('ocr_schedule_bad_');
        addTearDown(() => dir.delete(recursive: true));
        final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
        await cacheFile.writeAsString('{not valid json');

        final progress = await buildScheduledOcrProgress(
          cacheFilePath: cacheFile.path,
          reservedPages: 7,
        );

        expect(progress.status, OcrStatus.running);
        expect(progress.completed, 0);
        expect(progress.total, 7);
      },
    );

    test(
      'treats blank pages as complete when the OCR pass is marked complete',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'ocr_schedule_blank_complete_',
        );
        addTearDown(() => dir.delete(recursive: true));
        final cacheFile = File(p.join(dir.path, 'pages_cache.json'));
        await cacheFile.writeAsString(
          json.encode({
            'title': 'Finished OCR',
            'imageDirPath': dir.path,
            'ocrSource': 'custom_ocr',
            'ocrCompleted': true,
            'pages': [
              {
                'pageIndex': 0,
                'imageFileName': '0001.jpg',
                'imgWidth': 100,
                'imgHeight': 100,
                'blocks': const [],
              },
              {
                'pageIndex': 1,
                'imageFileName': '0002.jpg',
                'imgWidth': 100,
                'imgHeight': 100,
                'blocks': [
                  {
                    'box': [0.0, 0.0, 10.0, 10.0],
                    'vertical': true,
                    'fontSize': 12.0,
                    'linesCoords': const [],
                    'lines': ['text'],
                    'words': [
                      {
                        'surface': 'text',
                        'box': [0.0, 0.0, 5.0, 5.0],
                        'blockIdx': 0,
                        'lineIdx': 0,
                        'charStart': 0,
                        'charEnd': 4,
                      },
                    ],
                  },
                ],
              },
            ],
          }),
        );

        final progress = await buildScheduledOcrProgress(
          cacheFilePath: cacheFile.path,
        );

        expect(progress.status, OcrStatus.running);
        expect(progress.completed, 2);
        expect(progress.total, 2);
      },
    );
  });
}
