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
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/http_transport.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/data/services/aozora_catalog.dart';
import 'package:mekuru/features/free_books/data/services/aozora_download.dart';
import 'package:mekuru/features/free_books/data/services/tadoku_catalog.dart';
import 'package:mekuru/features/free_books/data/services/tadoku_covers.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show announce, navigatorKey;
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The tab the Free books screen shows: kept while the app runs.
final freeBooksTabProvider = StateProvider<int>((ref) => 0);

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

/// The bundled catalog of Tadoku graded readers (about 140, so parsed in
/// place).
final tadokuCatalogProvider = FutureProvider.autoDispose<List<TadokuBook>>(
  (ref) async => parseTadokuCatalog(
    await rootBundle.loadString('assets/free_books/tadoku.json'),
  ),
);

/// Graded-reader covers on disk, in the app's cache folder: kept between
/// launches (unlike the temporary folder, which iOS empties), and out of
/// iCloud backups. One for the app's life, so it remembers covers on their
/// way and recent failures.
final tadokuCoversProvider = Provider<TadokuCovers>(
  (ref) => TadokuCovers(
    getApplicationCacheDirectory().then(
      (cache) => Directory(p.join(cache.path, 'tadoku_covers')),
    ),
  ),
);

/// A graded reader's cover, through [tadokuCoversProvider]: the manga
/// reader clears the image cache when it closes, and tadoku.org limits
/// request rates.
final tadokuCoverProvider = FutureProvider.autoDispose.family<File, Uri>(
  (ref, url) => ref.watch(tadokuCoversProvider).cover(url),
);

/// Search, filters and sort on the Aozora tab. Kept while the app runs and
/// reset at the next launch (Matt's call), starting on the easy picks.
final aozoraQueryProvider = StateProvider<AozoraQuery>(
  (ref) => AozoraQuery.easyPicks,
);

/// Search and filters on the Graded readers tab, kept like
/// [aozoraQueryProvider].
final tadokuQueryProvider = StateProvider<TadokuQuery>(
  (ref) => const TadokuQuery(),
);

/// Free books in the library by where they were downloaded from
/// ([Book.sourceId]: an [aozoraDownloadKey] or [tadokuDownloadKey]), for
/// "in your library". Never by title: hundreds of Aozora works share one.
final freeBooksInLibraryProvider = Provider.autoDispose<Map<String, Book>>((
  ref,
) {
  final books = ref.watch(booksProvider).value ?? const <Book>[];
  return {for (final book in books) ?book.sourceId: book};
});

/// The Aozora tab's list: the catalog through the current query. The
/// library is watched only when the query hides its books, so library writes
/// (every import, progress sync) don't re-sort the catalog for nothing.
final aozoraResultsProvider =
    Provider.autoDispose<AsyncValue<List<AozoraWork>>>((ref) {
      final query = ref.watch(aozoraQueryProvider);
      final inLibrary = query.hideInLibrary
          ? ref.watch(freeBooksInLibraryProvider)
          : const <String, Book>{};
      return ref
          .watch(aozoraCatalogProvider)
          .whenData(
            (works) => filterAndSortWorks(
              works,
              query,
              isInLibrary: (work) =>
                  inLibrary.containsKey(aozoraDownloadKey(work)),
            ),
          );
    });

/// The Graded readers tab's grid: the catalog through the current query.
final tadokuResultsProvider =
    Provider.autoDispose<AsyncValue<List<TadokuBook>>>((ref) {
      final query = ref.watch(tadokuQueryProvider);
      final inLibrary = query.hideInLibrary
          ? ref.watch(freeBooksInLibraryProvider)
          : const <String, Book>{};
      return ref
          .watch(tadokuCatalogProvider)
          .whenData(
            (books) => filterTadokuBooks(
              books,
              query,
              isInLibrary: (book) =>
                  inLibrary.containsKey(tadokuDownloadKey(book)),
            ),
          );
    });

/// Where Aozora's card folders live; tests point it at a local server.
final aozoraBaseUrlProvider = Provider<String>((ref) => aozoraCardsBase);

/// The download key of [work] in [freeBookDownloadProvider].
String aozoraDownloadKey(AozoraWork work) => 'aozora:${work.id}';

/// The download key of [book] in [freeBookDownloadProvider].
String tadokuDownloadKey(TadokuBook book) => '$_tadokuKeyPrefix${book.id}';

const _tadokuKeyPrefix = 'tadoku:';

/// Whether [book] is a graded reader downloaded from Tadoku: a PDF of
/// scanned text pages, which on-device OCR reads with the NDL text model.
bool isTadokuDownload(Book book) =>
    book.sourceId?.startsWith(_tadokuKeyPrefix) ?? false;

/// Free-book downloads in progress, keyed `aozora:<id>` or `tadoku:<id>`,
/// valued 0..1 (0 = indeterminate). Downloads run in the app; they outlive
/// the screen, so results are announced through the global messenger.
class FreeBookDownloadNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  /// Downloads [work], converts it to an EPUB and imports it.
  Future<void> downloadAozora(AozoraWork work) => _download(
    aozoraDownloadKey(work),
    source: 'aozora',
    fileName: 'aozora_${work.id}.epub',
    format: 'epub',
    fetch: (client, path, onProgress) async {
      final bytes = await fetchAozoraEpub(
        work,
        IOClient(client),
        base: ref.read(aozoraBaseUrlProvider),
        onProgress: onProgress,
      );
      await File(path).writeAsBytes(bytes, flush: true);
    },
  );

  /// Downloads [book]'s PDF from tadoku.org and imports it, unchanged.
  Future<void> downloadTadoku(TadokuBook book) => _download(
    tadokuDownloadKey(book),
    source: 'tadoku',
    fileName: 'tadoku_${book.id}.pdf',
    format: 'pdf',
    title: book.title,
    fetch: (client, path, onProgress) => downloadToFile(
      book.pdfUrl.toString(),
      path,
      client: client,
      onProgress: onProgress,
    ),
  );

  /// Share of the progress the download fills; the import fills the rest
  /// (as for dictionary downloads), so the iOS Live Activity keeps moving
  /// through a long PDF import and reaches 100% only when the book is in.
  static const _downloadShare = 0.7;

  /// One download: [fetch] writes the book to a temp file named [fileName]
  /// (by id: titles must stay out of paths, which reach error text), which
  /// then goes through the library's import as [format]. Registered so a
  /// full restore, or iOS ending the background task, can stop it.
  Future<void> _download(
    String key, {
    required String source,
    required String fileName,
    required String format,
    String? title,
    required Future<void> Function(
      HttpClient client,
      String path,
      void Function(double progress) onProgress,
    )
    fetch,
  }) async {
    if (state.containsKey(key)) return;
    state = {...state, key: 0};
    ref
        .read(freeBookDownloadFailuresProvider.notifier)
        .update((failures) => {...failures}..remove(key));
    final workId = 'download:$key';
    final client = HttpClient();
    InAppServerDownloads.start(key, client);
    // iOS or the user ended the background task, which the user is told;
    // a full restore also cancels, silently, as the app then restarts.
    var stoppedByUser = false;
    BackgroundWork.instance.start(
      workId,
      BackgroundJobKind.download,
      onStopped: () {
        stoppedByUser = true;
        InAppServerDownloads.cancel(key);
      },
    );
    bool cancelled() {
      if (!InAppServerDownloads.wasCancelled(key)) return false;
      if (stoppedByUser) announce((l10n) => l10n.serverBrowseDownloadStopped);
      return true;
    }

    void report(double progress) {
      BackgroundWork.instance.progress(workId, progress);
      if (ref.mounted) state = {...state, key: progress};
    }

    File? temp;
    try {
      temp = File(p.join((await getTemporaryDirectory()).path, fileName));
      await fetch(
        client,
        temp.path,
        (progress) => report(progress * _downloadShare),
      );
      if (!ref.mounted || cancelled()) return;
      final book = await ref
          .read(bookImportProvider.notifier)
          .importOne(
            temp.path,
            format: format,
            title: title,
            sourceId: key,
            onProgress: (progress) =>
                report(_downloadShare + (1 - _downloadShare) * progress),
          );
      report(1.0);
      if (!ref.mounted) return;
      logUsage(
        'free_books.download',
        attrs: {'source': source, 'outcome': 'ok'},
      );
      announce(
        (l10n) => l10n.serverBrowseAddedToLibrary(title: book.title),
        action: (l10n) => SnackBarAction(
          label: l10n.freeBooksRead,
          onPressed: () {
            final navigator = navigatorKey.currentState;
            if (navigator != null) openBookReader(navigator, book);
          },
        ),
      );
    } catch (error, stackTrace) {
      if (cancelled()) return;
      // TLS fails behind a captive portal or with a wrong clock, and a
      // stalled connection times out.
      final network =
          error is NetworkException ||
          error is HttpException ||
          error is SocketException ||
          error is TlsException ||
          error is TimeoutException;
      // A site offline is expected: a warning log, not a Sentry issue.
      logFailure(
        'free_books.download',
        error,
        stackTrace: network ? null : stackTrace,
        attrs: {'source': source},
      );
      String message(AppLocalizations l10n) =>
          network ? l10n.freeBooksDownloadFailed : l10n.freeBooksImportFailed;
      if (ref.mounted) {
        ref
            .read(freeBookDownloadFailuresProvider.notifier)
            .update((failures) => {...failures, key: message});
      }
      announce(message);
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

/// Why a free book's last download failed, by the keys of
/// [freeBookDownloadProvider]. The book's sheet shows it, as the sheet
/// covers the snack bar that announces it. Cleared when the download is
/// tried again.
final freeBookDownloadFailuresProvider =
    StateProvider<Map<String, String Function(AppLocalizations l10n)>>(
      (ref) => const {},
    );
