import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ocr_background_worker.dart';
import '../providers/ocr_progress_provider.dart';

/// Overlay widget displayed on top of book covers in the library grid
/// to show OCR processing progress.
///
/// Shows a semi-transparent overlay with:
/// - Page count (e.g., "42/200 pages")
/// - Estimated time remaining
/// - Linear progress bar at the bottom
class OcrProgressOverlay extends ConsumerWidget {
  final int bookId;

  const OcrProgressOverlay({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(ocrProgressProvider(bookId));

    return progressAsync.when(
      data: (progress) {
        if (progress == null) return const SizedBox.shrink();
        if (progress.status == OcrStatus.idle) return const SizedBox.shrink();

        // Show "Completed" briefly, then hide
        if (progress.status == OcrStatus.completed) {
          return _CompletedOverlay();
        }

        if (progress.status == OcrStatus.failed) {
          return _StatusOverlay(label: 'OCR Failed', color: Colors.red);
        }

        if (progress.status == OcrStatus.cancelled &&
            progress.completed > 0 &&
            progress.completed < progress.total) {
          return _PausedOverlay(
            completed: progress.completed,
            total: progress.total,
          );
        }

        if (progress.status == OcrStatus.running) {
          return _RunningOverlay(progress: progress);
        }

        return const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _RunningOverlay extends StatelessWidget {
  final OcrProgress progress;

  const _RunningOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    final fraction = progress.total > 0
        ? progress.completed / progress.total
        : 0.0;

    // Calculate ETA
    String etaText = '';
    if (progress.avgSecondsPerPage != null && progress.avgSecondsPerPage! > 0) {
      final remaining = progress.total - progress.completed;
      final etaSeconds = (remaining * progress.avgSecondsPerPage!).round();
      if (etaSeconds < 60) {
        etaText = '~${etaSeconds}s remaining';
      } else if (etaSeconds < 3600) {
        etaText = '~${(etaSeconds / 60).ceil()} min remaining';
      } else {
        final hours = etaSeconds ~/ 3600;
        final mins = (etaSeconds % 3600) ~/ 60;
        etaText = '~${hours}h ${mins}m remaining';
      }
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${progress.completed}/${progress.total} pages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (etaText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                etaText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  final int completed;
  final int total;

  const _PausedOverlay({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.pause_circle_outline,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              '$completed/$total pages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'OCR Paused',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.green.withValues(alpha: 0.7),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 32),
            SizedBox(height: 4),
            Text(
              'OCR Complete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusOverlay({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: color.withValues(alpha: 0.7),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
