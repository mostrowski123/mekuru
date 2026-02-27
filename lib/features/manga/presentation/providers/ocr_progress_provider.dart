import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/ocr_background_worker.dart';

/// Provides OCR progress for a specific book by polling SharedPreferences.
///
/// The WorkManager background task writes progress to SharedPreferences,
/// and this provider polls every 2 seconds to pick up changes.
/// Returns null if no OCR task has been started for this book.
final ocrProgressProvider =
    StreamProvider.family<OcrProgress?, int>((ref, bookId) {
  return _pollOcrProgress(bookId);
});

Stream<OcrProgress?> _pollOcrProgress(int bookId) async* {
  while (true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Reload to pick up changes from other processes
    final progress = OcrProgress.load(prefs, bookId);
    yield progress;

    // Stop polling if completed, cancelled, or failed
    if (progress != null &&
        (progress.status == OcrStatus.completed ||
            progress.status == OcrStatus.cancelled ||
            progress.status == OcrStatus.failed)) {
      // Yield one final time, then stop
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// Whether OCR is actively running for a specific book.
final isOcrRunningProvider = Provider.family<bool, int>((ref, bookId) {
  final progress = ref.watch(ocrProgressProvider(bookId));
  return progress.whenOrNull(data: (p) => p?.status == OcrStatus.running) ??
      false;
});

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
