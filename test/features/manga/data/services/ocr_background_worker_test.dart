import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('defaultOcrServerUrl is a valid URL', () {
      expect(Uri.tryParse(defaultOcrServerUrl), isNotNull);
      expect(defaultOcrServerUrl, startsWith('https://'));
    });
  });
}
