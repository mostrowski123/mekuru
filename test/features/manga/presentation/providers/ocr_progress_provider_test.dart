import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('remoteOcrChange', () {
    AsyncValue<OcrProgress?> at(String status, [int completed = 0]) =>
        AsyncData(OcrProgress(completed: completed, total: 10, status: status));

    test('the first value is never a change', () {
      final failed = at(OcrStatus.failed);
      expect(remoteOcrChange(null, failed), RemoteOcrChange.none);
      expect(
        remoteOcrChange(const AsyncLoading(), failed),
        RemoteOcrChange.none,
      );
    });

    test('a running job that fails is reported once', () {
      final failed = at(OcrStatus.failed);
      expect(
        remoteOcrChange(at(OcrStatus.running), failed),
        RemoteOcrChange.failed,
      );
      expect(remoteOcrChange(failed, failed), RemoteOcrChange.none);
    });

    test('new pages and a finished job reload the reader', () {
      expect(
        remoteOcrChange(at(OcrStatus.running, 3), at(OcrStatus.running, 4)),
        RemoteOcrChange.pagesCommitted,
      );
      expect(
        remoteOcrChange(at(OcrStatus.running, 3), at(OcrStatus.running, 3)),
        RemoteOcrChange.none,
      );
      // Replacing one page of a fully recognized manga never raises the count.
      expect(
        remoteOcrChange(at(OcrStatus.running, 9), at(OcrStatus.completed, 10)),
        RemoteOcrChange.pagesCommitted,
      );
      expect(
        remoteOcrChange(const AsyncData(null), at(OcrStatus.completed, 10)),
        RemoteOcrChange.pagesCommitted,
      );
    });

    test('a first scheduled job and a cleared state change nothing', () {
      expect(
        remoteOcrChange(const AsyncData(null), at(OcrStatus.running, 5)),
        RemoteOcrChange.none,
      );
      expect(
        remoteOcrChange(at(OcrStatus.completed, 10), const AsyncData(null)),
        RemoteOcrChange.none,
      );
    });

    test('a refresh that lands on failed is a job that died before the first '
        'poll', () async {
      final provider = StreamProvider<OcrProgress?>(
        (ref) => Stream.value(at(OcrStatus.failed).value),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final changes = <RemoteOcrChange>[];
      container.listen(
        provider,
        (previous, next) => changes.add(remoteOcrChange(previous, next)),
      );
      await container.read(provider.future);
      expect(changes, everyElement(RemoteOcrChange.none));

      container.invalidate(provider);
      await container.read(provider.future);
      expect(changes.where((c) => c != RemoteOcrChange.none), [
        RemoteOcrChange.failed,
      ]);
    });
  });

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

    test('stops polling when status is idle', () async {
      const progress = OcrProgress(
        completed: 0,
        total: 0,
        status: OcrStatus.idle,
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
      expect(state.value!.status, OcrStatus.idle);
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
