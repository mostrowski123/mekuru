import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/l10n/l10n.dart';
import '../../data/services/ocr_background_worker.dart';
import '../providers/local_ocr_providers.dart';
import '../providers/ocr_progress_provider.dart';
import 'local_ocr_widgets.dart';

/// Sits above the existing page widget without replacing it or its zoom state.
class LocalOcrPageOverlay extends ConsumerWidget {
  final int bookId;
  final List<int> visiblePages;
  const LocalOcrPageOverlay({
    super.key,
    required this.bookId,
    required this.visiblePages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // iOS runs every scan through the page loop, which keeps no job journal;
    // without this the reader is silent until "OCR complete".
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final progress = ref.watch(ocrProgressProvider(bookId)).asData?.value;
      if (progress?.status != OcrStatus.running) return const SizedBox.shrink();
      return _PageLoopProgress(bookId: bookId, progress: progress!);
    }
    final launch = ref.watch(
      localOcrLaunchesProvider.select((all) => all[bookId]),
    );
    final job = ref.watch(localOcrJobProvider(bookId));
    final pending = launch != null && launch.job == null;
    final error = launch?.error;
    if (!pending && !(job?.isActive ?? false) && error == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final targets =
        (pending
            ? launch.spec.pages
            : (job?.json['pages'] as List?)?.cast<int>()) ??
        const <int>[];
    final onPage = targets.any(
      (page) =>
          visiblePages.contains(page) &&
          !(job?.outcomes.containsKey(page.toString()) ?? false),
    );
    final cancelling =
        launch?.cancelling == true || job?.status == 'cancelling';
    final regionsDone = (job?.json['regionsDone'] as num?)?.toInt() ?? 0;
    final regionsTotal = (job?.json['regionsTotal'] as num?)?.toInt() ?? 0;
    final eta = job == null ? '' : localOcrEta(context, job);
    final panel = Material(
      color: Colors.black.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle(
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Text(localOcrReason(context, error))
              else ...[
                Text(
                  cancelling
                      ? l.localOcrCancelling
                      : pending
                      ? l.localOcrPreparing
                      : localOcrPhase(context, job!),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: regionsTotal > 0 && job?.phase == 'recognizing'
                      ? (regionsDone / regionsTotal).clamp(0, 1)
                      : null,
                ),
                const SizedBox(height: 12),
                if (job?.json['currentPage'] is num)
                  Text(
                    l.localOcrCurrentPage(
                      page: (job!.json['currentPage'] as num).toInt() + 1,
                    ),
                  ),
                if (regionsTotal > 0)
                  Text(
                    l.localOcrReadingRegions(
                      done: regionsDone,
                      total: regionsTotal,
                    ),
                  ),
                if ((job?.total ?? targets.length) > 1)
                  Text(
                    l.localOcrProgress(
                      processed: job?.processed ?? 0,
                      total: job?.total ?? targets.length,
                    ),
                  ),
                Text(eta.isEmpty ? l.localOcrEstimating : eta),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: cancelling
                    ? null
                    : error != null
                    ? () => ref
                          .read(localOcrLaunchesProvider.notifier)
                          .dismiss(bookId)
                    : () => runLocalOcrAction(context, () async {
                        if (pending) {
                          await ref
                              .read(localOcrLaunchesProvider.notifier)
                              .cancel(bookId);
                        } else {
                          await ref
                              .read(localOcrLaunchesProvider.notifier)
                              .cancel(bookId, currentJob: job);
                        }
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white60,
                ),
                child: Text(error != null ? l.commonClose : l.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
    return Positioned.fill(
      child: Stack(
        children: [
          if (onPage || error != null)
            const Positioned.fill(child: ColoredBox(color: Color(0x55000000))),
          // Completed pages remain readable while a volume job works elsewhere.
          Align(
            alignment: onPage || error != null
                ? Alignment.center
                : Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: panel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress of an iOS page-loop scan, kept at the bottom so pages stay
/// readable while the rest of the volume is scanned.
class _PageLoopProgress extends ConsumerWidget {
  final int bookId;
  final OcrProgress progress;
  const _PageLoopProgress({required this.bookId, required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: Colors.black.withValues(alpha: .78),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.localOcrProgress(
                                processed: progress.completed,
                                total: progress.total,
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progress.total > 0
                                  ? progress.completed / progress.total
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await cancelOcrTask(bookId);
                          ref.invalidate(ocrProgressProvider(bookId));
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l.localOcrPause),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
