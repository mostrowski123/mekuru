import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import '../../data/services/local_ocr_client.dart';
import '../../data/services/manga_cache_store.dart';
import '../../data/models/mokuro_models.dart';

final localOcrClientProvider = Provider<LocalOcrClient>(
  (ref) => const NativeLocalOcrClient(),
);
final ocrBookLoaderProvider = Provider<Future<MokuroBook> Function(String)>(
  (ref) => MangaCacheStore.read,
);

Stream<T> _poll<T>(Ref ref, Future<T> Function() read) {
  final controller = StreamController<T>();
  var busy = false;
  Future<void> refresh() async {
    if (busy || controller.isClosed) return;
    busy = true;
    try {
      final value = await read();
      if (!controller.isClosed) controller.add(value);
    } catch (error, stack) {
      if (!controller.isClosed) controller.addError(error, stack);
    } finally {
      busy = false;
    }
  }

  final timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  unawaited(refresh());
  return controller.stream;
}

final localOcrJobsProvider = StreamProvider.autoDispose<List<OcrJobProgress>>(
  (ref) => LocalMangaOcr.available
      ? _poll(ref, LocalMangaOcr.jobs)
      : Stream.value(const []),
);

// autoDispose: a keep-alive family here pinned the 1 Hz journal poll for the
// life of the app once any manga tile had rendered.
final localOcrJobProvider = Provider.autoDispose.family<OcrJobProgress?, int>((
  ref,
  bookId,
) {
  final jobs = ref.watch(localOcrJobsProvider).asData?.value ?? const [];
  final matching = jobs.where((j) => j.bookId == bookId).toList();
  final launch = ref.watch(
    localOcrLaunchesProvider.select((all) => all[bookId]),
  );
  final seeded = launch?.job;
  // The launch seed only bridges the gap until the journal poll reports the
  // job; it expires so a job deleted later (dismissed, pruned) cannot resurface.
  if (seeded != null &&
      launch!.isFresh &&
      !jobs.any((job) => job.id == seeded.id)) {
    return seeded;
  }
  return matching.isEmpty ? null : matching.last;
});

final localOcrModelProvider = StreamProvider.autoDispose<OcrModelState>(
  (ref) => LocalMangaOcr.available
      ? _poll(ref, LocalMangaOcr.modelState)
      : Stream.value(const OcrModelState({'supported': false})),
);

/// The native journal is polled, but launch feedback must not wait for a poll.
/// This controller also owns cancellation while job creation is still in flight.
class LocalOcrLaunch {
  final OcrJobSpec spec;
  final bool cancelling;
  final OcrJobProgress? job;
  final String? error;
  final DateTime? seededAt;
  const LocalOcrLaunch(
    this.spec, {
    this.cancelling = false,
    this.job,
    this.error,
    this.seededAt,
  });

  bool get isFresh =>
      seededAt != null &&
      DateTime.now().difference(seededAt!) < const Duration(seconds: 15);
}

class LocalOcrLaunches extends Notifier<Map<int, LocalOcrLaunch>> {
  @override
  Map<int, LocalOcrLaunch> build() => {};

  Future<void> start(OcrJobSpec spec, Future<void> Function() prepare) async {
    final id = spec.bookId;
    final old = state[id];
    if (old != null && old.error == null && old.job == null) return;
    final client = ref.read(localOcrClientProvider);
    state = {...state, id: LocalOcrLaunch(spec)};
    try {
      await prepare();
      if (state[id]?.cancelling == true) {
        dismiss(id);
        return;
      }
      final job = await client.start(spec);
      if (state[id]?.cancelling == true) {
        await client.cancel(job.id);
        dismiss(id);
      } else {
        state = {
          ...state,
          id: LocalOcrLaunch(spec, job: job, seededAt: DateTime.now()),
        };
      }
      ref.invalidate(localOcrJobsProvider);
    } catch (error) {
      state = {
        ...state,
        id: LocalOcrLaunch(
          spec,
          error: error is PlatformException ? error.code : error.toString(),
        ),
      };
    }
  }

  Future<void> cancel(int bookId, {OcrJobProgress? currentJob}) async {
    final launch =
        state[bookId] ??
        (currentJob == null
            ? null
            : LocalOcrLaunch(
                OcrJobSpec(
                  bookId: bookId,
                  title: '',
                  cachePath: '',
                  pages: (currentJob.json['pages'] as List).cast<int>(),
                ),
                job: currentJob,
              ));
    if (launch == null) return;
    state = {
      ...state,
      bookId: LocalOcrLaunch(
        launch.spec,
        cancelling: true,
        job: launch.job,
        seededAt: launch.seededAt,
      ),
    };
    if (launch.job != null) {
      try {
        await ref.read(localOcrClientProvider).cancel(launch.job!.id);
        // Keep immediate cancellation feedback until the journal reports the
        // terminal state; do not re-enable Cancel during the next poll.
        ref.invalidate(localOcrJobsProvider);
      } catch (error) {
        state = {
          ...state,
          bookId: LocalOcrLaunch(
            launch.spec,
            job: launch.job,
            error: error is PlatformException ? error.code : error.toString(),
          ),
        };
      }
    }
  }

  void dismiss(int bookId) => state = {...state}..remove(bookId);
}

final localOcrLaunchesProvider =
    NotifierProvider<LocalOcrLaunches, Map<int, LocalOcrLaunch>>(
      LocalOcrLaunches.new,
    );
