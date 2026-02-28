import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ocrProgressProvider', () {
    test('emits null when no progress stored', () async {
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Listen to the stream provider
      final sub = container.listen(ocrProgressProvider(999), (_, _) {});

      // Wait for first emission
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = sub.read();
      expect(state.hasValue, isTrue);
      expect(state.value, isNull);
    });

    test('emits progress when stored in SharedPreferences', () async {
      const progress = OcrProgress(
        completed: 10,
        total: 50,
        status: OcrStatus.running,
        avgSecondsPerPage: 1.0,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(ocrProgressProvider(42), (_, _) {});

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = sub.read();
      expect(state.hasValue, isTrue);
      expect(state.value, isNotNull);
      expect(state.value!.completed, 10);
      expect(state.value!.total, 50);
      expect(state.value!.status, OcrStatus.running);
    });

    test('stops polling when status is completed', () async {
      const progress = OcrProgress(
        completed: 50,
        total: 50,
        status: OcrStatus.completed,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(ocrProgressProvider(42), (_, _) {});

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = sub.read();
      expect(state.hasValue, isTrue);
      expect(state.value!.status, OcrStatus.completed);
    });
  });

  group('isOcrRunningProvider', () {
    test('returns false when no progress stored', () async {
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Need to wait for the stream provider to emit
      container.listen(ocrProgressProvider(999), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final isRunning = container.read(isOcrRunningProvider(999));
      expect(isRunning, isFalse);
    });

    test('returns true when status is running', () async {
      const progress = OcrProgress(
        completed: 5,
        total: 50,
        status: OcrStatus.running,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(42), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final isRunning = container.read(isOcrRunningProvider(42));
      expect(isRunning, isTrue);
    });

    test('returns false when status is completed', () async {
      const progress = OcrProgress(
        completed: 50,
        total: 50,
        status: OcrStatus.completed,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(42), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final isRunning = container.read(isOcrRunningProvider(42));
      expect(isRunning, isFalse);
    });
  });

  group('hasPartialOcrProvider', () {
    test('returns false when no progress stored', () async {
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(999), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final hasPartial = container.read(hasPartialOcrProvider(999));
      expect(hasPartial, isFalse);
    });

    test('returns true when cancelled with partial progress', () async {
      const progress = OcrProgress(
        completed: 10,
        total: 50,
        status: OcrStatus.cancelled,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(42), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final hasPartial = container.read(hasPartialOcrProvider(42));
      expect(hasPartial, isTrue);
    });

    test('returns false when fully completed', () async {
      const progress = OcrProgress(
        completed: 50,
        total: 50,
        status: OcrStatus.completed,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(42), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final hasPartial = container.read(hasPartialOcrProvider(42));
      expect(hasPartial, isFalse);
    });

    test('returns false when running (active processing)', () async {
      const progress = OcrProgress(
        completed: 10,
        total: 50,
        status: OcrStatus.running,
      );

      SharedPreferences.setMockInitialValues({
        '${ocrProgressKeyPrefix}42': progress.toJson(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(ocrProgressProvider(42), (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final hasPartial = container.read(hasPartialOcrProvider(42));
      expect(hasPartial, isFalse);
    });
  });
}
