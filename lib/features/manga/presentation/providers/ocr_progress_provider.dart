import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/ocr_background_worker.dart';

/// Provides OCR progress for a specific book by polling SharedPreferences.
///
/// The WorkManager background task writes progress to SharedPreferences,
/// and this provider polls every 2 seconds to pick up changes.
/// Returns null if no OCR task has been started for this book.
final ocrProgressProvider = StreamProvider.family<OcrProgress?, int>((
  ref,
  bookId,
) {
  return _pollOcrProgress(bookId);
});

Stream<OcrProgress?> _pollOcrProgress(int bookId) async* {
  while (true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Reload to pick up changes from other processes
    final progress = OcrProgress.load(prefs, bookId);
    yield progress;

    // Stop polling if the task is no longer active.
    if (progress != null &&
        (progress.status == OcrStatus.completed ||
            progress.status == OcrStatus.cancelled ||
            progress.status == OcrStatus.failed ||
            progress.status == OcrStatus.idle)) {
      // Yield one final time, then stop
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// What a step in remote OCR progress means for a reader that is open on the
/// book.
enum RemoteOcrChange { none, pagesCommitted, failed }

/// Classifies the step from [previous] to [next]. The provider's first value
/// is never a change, so a failure left over from an earlier run stays quiet
/// when the reader opens.
RemoteOcrChange remoteOcrChange(
  AsyncValue<OcrProgress?>? previous,
  AsyncValue<OcrProgress?> next,
) {
  final after = next.value;
  if (previous?.hasValue != true || next.isLoading || after == null) {
    return RemoteOcrChange.none;
  }
  final before = previous!.value;
  if (after.status == OcrStatus.failed) {
    // Scheduling overwrites the old state with `running` before it refreshes
    // this provider, so a refresh that lands on `failed` is a new job that
    // died before the first poll.
    return previous.isLoading || before?.status != OcrStatus.failed
        ? RemoteOcrChange.failed
        : RemoteOcrChange.none;
  }
  final finished =
      after.status == OcrStatus.completed &&
      before?.status != OcrStatus.completed;
  return finished || (before != null && after.completed > before.completed)
      ? RemoteOcrChange.pagesCommitted
      : RemoteOcrChange.none;
}

/// Whether a book has partial OCR data (some pages processed, but not all).
final hasPartialOcrProvider = Provider.family<bool, int>((ref, bookId) {
  final progress = ref.watch(ocrProgressProvider(bookId));
  return progress.whenOrNull(
        data: (p) =>
            p != null &&
            p.status != OcrStatus.running &&
            p.completed > 0 &&
            p.completed < p.total,
      ) ??
      false;
});
