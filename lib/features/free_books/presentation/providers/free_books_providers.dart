import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy barrel in Riverpod 3 (still supported).
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/io_client.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/background_work.dart';
import 'package:mekuru/core/services/http_transport.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/services/aozora_catalog.dart';
import 'package:mekuru/features/free_books/data/services/aozora_download.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/main.dart' show announce, navigatorKey;
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The bundled Aozora catalog, parsed off the UI isolate. autoDispose, so
/// its ~17,000 works (about 8 MB) are freed when the Free books screen
/// closes; a book opened from there is read on top of it, so they stay
/// while it is read. Loaded as bytes: `loadString` would keep the decoded
/// 4 MB string in rootBundle's cache for the life of the app.
final aozoraCatalogProvider = FutureProvider.autoDispose<List<AozoraWork>>((
  ref,
) async {
  final data = await rootBundle.load('assets/free_books/aozora.json');
  return compute(
    (ByteData bytes) => parseAozoraCatalog(
      utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    ),
    data,
  );
});

/// Search, filters and sort on the Aozora tab. Kept while the app runs and
/// reset at the next launch (Matt's call), starting on the easy picks.
final aozoraQueryProvider = StateProvider<AozoraQuery>(
  (ref) => AozoraQuery.easyPicks,
);

/// The reader's own EPUB pace, or the learner default until their stats can
/// say; `personal` tells the copy which one it is.
final readingPaceProvider =
    Provider.autoDispose<({double charsPerMinute, bool personal})>((ref) {
      final sessions = ref.watch(sessionsProvider).value;
      final pace = sessions == null
          ? null
          : readingPaceCharsPerMinute(sessions);
      return pace == null
          ? (charsPerMinute: defaultReadingPaceCharsPerMinute, personal: false)
          : (charsPerMinute: pace, personal: true);
    });

/// EPUB library books by normalized title — the app's book identity
/// ([BookMatchService.normalizeTitle]) — for "in your library".
final epubBooksByTitleProvider = Provider.autoDispose<Map<String, Book>>((ref) {
  final books = ref.watch(booksProvider).value ?? const <Book>[];
  return {
    for (final book in books)
      if (book.bookType == 'epub')
        BookMatchService.normalizeTitle(book.title): book,
  };
});

/// The library copy of [work], if there is one.
Book? libraryCopyOf(Map<String, Book> byTitle, AozoraWork work) =>
    byTitle[BookMatchService.normalizeTitle(work.displayTitle)];

/// The Aozora tab's list: the catalog through the current query. Pace and
/// library are watched only when the query uses them, so library writes
/// (every import, progress sync) don't re-sort the catalog for nothing.
final aozoraResultsProvider =
    Provider.autoDispose<AsyncValue<List<AozoraWork>>>((ref) {
      final query = ref.watch(aozoraQueryProvider);
      final pace = query.lengths.isEmpty
          ? defaultReadingPaceCharsPerMinute
          : ref.watch(readingPaceProvider).charsPerMinute;
      final byTitle = query.hideInLibrary
          ? ref.watch(epubBooksByTitleProvider)
          : const <String, Book>{};
      return ref
          .watch(aozoraCatalogProvider)
          .whenData(
            (works) => filterAndSortWorks(
              works,
              query,
              charsPerMinute: pace,
              isInLibrary: (work) => libraryCopyOf(byTitle, work) != null,
            ),
          );
    });

/// Where Aozora's card folders live; tests point it at a local server.
final aozoraBaseUrlProvider = Provider<String>((ref) => aozoraCardsBase);

/// The download key of [work] in [freeBookDownloadProvider].
String aozoraDownloadKey(AozoraWork work) => 'aozora:${work.id}';

/// Free-book downloads in progress, keyed `aozora:<id>` (later also
/// `tadoku:<id>`), valued 0..1 (0 = indeterminate). Downloads run in the
/// app; they outlive the screen, so results are announced through the
/// global messenger.
class FreeBookDownloadNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  /// Downloads [work], converts it to an EPUB and imports it.
  Future<void> downloadAozora(AozoraWork work) async {
    final key = aozoraDownloadKey(work);
    if (state.containsKey(key)) return;
    state = {...state, key: 0};
    final workId = 'download:$key';
    final httpClient = HttpClient();
    // A full restore cancels every registered in-app download.
    InAppServerDownloads.start(key, httpClient);
    BackgroundWork.instance.start(
      workId,
      BackgroundJobKind.download,
      onStopped: () => InAppServerDownloads.cancel(key),
    );
    final client = IOClient(httpClient);
    File? temp;
    bool stopped() => !ref.mounted || InAppServerDownloads.wasCancelled(key);
    try {
      final bytes = await fetchAozoraEpub(
        work,
        client,
        base: ref.read(aozoraBaseUrlProvider),
      );
      if (stopped()) return;
      // Named by id: titles must stay out of paths, which reach error text.
      temp = File(
        p.join((await getTemporaryDirectory()).path, 'aozora_${work.id}.epub'),
      );
      await temp.writeAsBytes(bytes, flush: true);
      if (stopped()) return;
      final book = await ref.read(bookRepositoryProvider).importEpub(temp.path);
      if (!ref.mounted) return;
      await ref.read(bookImportProvider.notifier).applyPendingBackupData(book);
      logUsage(
        'free_books.download',
        attrs: {'source': 'aozora', 'outcome': 'ok'},
      );
      announce(
        (l10n) => l10n.serverBrowseAddedToLibrary(title: book.title),
        action: (l10n) => SnackBarAction(
          label: l10n.freeBooksRead,
          onPressed: () =>
              navigatorKey.currentState?.push(bookReaderRoute(book)),
        ),
      );
    } catch (error, stackTrace) {
      if (InAppServerDownloads.wasCancelled(key)) return;
      final network = error is NetworkException || error is HttpException;
      // Aozora offline is expected: a warning log, not a Sentry issue.
      logFailure(
        'free_books.download',
        error,
        stackTrace: network ? null : stackTrace,
        attrs: {'source': 'aozora'},
      );
      announce(
        (l10n) => network
            ? l10n.freeBooksAozoraDownloadFailed
            : l10n.freeBooksConversionFailed,
      );
    } finally {
      client.close();
      InAppServerDownloads.finish(key);
      BackgroundWork.instance.finish(workId);
      final file = temp;
      if (file != null) unawaited(_deleteQuietly(file));
      if (ref.mounted) state = {...state}..remove(key);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Temp space; the OS clears it eventually.
    }
  }
}

final freeBookDownloadProvider =
    NotifierProvider<FreeBookDownloadNotifier, Map<String, double>>(
      FreeBookDownloadNotifier.new,
    );
