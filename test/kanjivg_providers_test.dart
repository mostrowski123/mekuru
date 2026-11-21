import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/shared/downloads/download.dart';

void main() {
  group('KanjiVgState', () {
    test('default state is not downloaded, not downloading', () {
      const state = KanjiVgState();
      expect(state.isDownloaded, isFalse);
      expect(state.isDownloading, isFalse);
      expect(state.isDeleting, isFalse);
      expect(state.progress, 0.0);
      expect(state.fileCount, 0);
      expect(state.outcome, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      const state = KanjiVgState(isDownloaded: true, fileCount: 100);
      final updated = state.copyWith(progress: 0.5);
      expect(updated.isDownloaded, isTrue);
      expect(updated.fileCount, 100);
      expect(updated.progress, 0.5);
    });

    test('copyWith can set fields to new values', () {
      const state = KanjiVgState();
      final updated = state.copyWith(isDownloading: true, progress: 0.75);
      expect(updated.isDownloading, isTrue);
      expect(updated.progress, 0.75);
      expect(updated.isDownloaded, isFalse);
    });

    test('copyWith clears the outcome when not passed', () {
      const state = KanjiVgState(
        outcome: (action: TileAction.download, error: null),
      );
      expect(state.copyWith(isDownloading: true).outcome, isNull);
    });

    test('copyWith can set the outcome', () {
      const state = KanjiVgState();
      final updated = state.copyWith(
        outcome: (action: TileAction.delete, error: null),
      );
      expect(updated.outcome, (action: TileAction.delete, error: null));
    });
  });
}
