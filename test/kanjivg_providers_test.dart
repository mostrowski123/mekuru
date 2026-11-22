import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';
import 'package:mekuru/shared/downloads/download.dart';

void main() {
  group('DownloadTileState', () {
    test('default state is not downloaded, not downloading', () {
      const state = DownloadTileState();
      expect(state.isInstalled, isFalse);
      expect(state.isDownloading, isFalse);
      expect(state.isDeleting, isFalse);
      expect(state.progress, 0.0);
      expect(state.fileCount, 0);
      expect(state.outcome, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      const state = DownloadTileState(isInstalled: true, fileCount: 100);
      final updated = state.copyWith(progress: 0.5);
      expect(updated.isInstalled, isTrue);
      expect(updated.fileCount, 100);
      expect(updated.progress, 0.5);
    });

    test('copyWith can set fields to new values', () {
      const state = DownloadTileState();
      final updated = state.copyWith(isDownloading: true, progress: 0.75);
      expect(updated.isDownloading, isTrue);
      expect(updated.progress, 0.75);
      expect(updated.isInstalled, isFalse);
    });

    test('copyWith clears the outcome when not passed', () {
      const state = DownloadTileState(
        outcome: (action: TileAction.download, error: null),
      );
      expect(state.copyWith(isDownloading: true).outcome, isNull);
    });

    test('copyWith can set the outcome', () {
      const state = DownloadTileState();
      final updated = state.copyWith(
        outcome: (action: TileAction.delete, error: null),
      );
      expect(updated.outcome, (action: TileAction.delete, error: null));
    });
  });
}
