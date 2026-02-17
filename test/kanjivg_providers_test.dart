import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';

void main() {
  group('KanjiVgState', () {
    test('default state is not downloaded, not downloading', () {
      const state = KanjiVgState();
      expect(state.isDownloaded, isFalse);
      expect(state.isDownloading, isFalse);
      expect(state.isDeleting, isFalse);
      expect(state.progress, 0.0);
      expect(state.fileCount, 0);
      expect(state.error, isNull);
      expect(state.successMessage, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      const state = KanjiVgState(
        isDownloaded: true,
        fileCount: 100,
      );
      final updated = state.copyWith(progress: 0.5);
      expect(updated.isDownloaded, isTrue);
      expect(updated.fileCount, 100);
      expect(updated.progress, 0.5);
    });

    test('copyWith can set fields to new values', () {
      const state = KanjiVgState();
      final updated = state.copyWith(
        isDownloading: true,
        progress: 0.75,
      );
      expect(updated.isDownloading, isTrue);
      expect(updated.progress, 0.75);
      expect(updated.isDownloaded, isFalse);
    });

    test('copyWith clears error and successMessage when not passed', () {
      const state = KanjiVgState(
        error: 'something failed',
        successMessage: 'success',
      );
      // error and successMessage are nullable and not forwarded by default
      final updated = state.copyWith(isDownloading: true);
      expect(updated.error, isNull);
      expect(updated.successMessage, isNull);
    });

    test('copyWith can set error', () {
      const state = KanjiVgState();
      final updated = state.copyWith(error: 'network error');
      expect(updated.error, 'network error');
      expect(updated.successMessage, isNull);
    });

    test('copyWith can set success message', () {
      const state = KanjiVgState();
      final updated = state.copyWith(successMessage: 'Downloaded 100 files.');
      expect(updated.successMessage, 'Downloaded 100 files.');
      expect(updated.error, isNull);
    });

    test('represents downloading state correctly', () {
      const downloading = KanjiVgState(
        isDownloading: true,
        progress: 0.45,
      );
      expect(downloading.isDownloading, isTrue);
      expect(downloading.isDownloaded, isFalse);
      expect(downloading.progress, 0.45);
    });

    test('represents downloaded state correctly', () {
      const downloaded = KanjiVgState(
        isDownloaded: true,
        fileCount: 12000,
        successMessage: 'Downloaded 12000 kanji stroke order files.',
      );
      expect(downloaded.isDownloaded, isTrue);
      expect(downloaded.isDownloading, isFalse);
      expect(downloaded.fileCount, 12000);
      expect(downloaded.successMessage, contains('12000'));
    });

    test('represents error state correctly', () {
      const error = KanjiVgState(
        error: 'Download failed: network timeout',
      );
      expect(error.isDownloaded, isFalse);
      expect(error.isDownloading, isFalse);
      expect(error.error, contains('network timeout'));
    });
  });
}
