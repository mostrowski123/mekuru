import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/main.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';

// ──────────────── Sort ────────────────

/// Sort orders available in the library.
enum LibrarySortOrder { dateAdded, lastRead, alphabetical }

LibrarySortOrder _sortOrderFromString(String? value) => switch (value) {
  'lastRead' => LibrarySortOrder.lastRead,
  'alphabetical' => LibrarySortOrder.alphabetical,
  _ => LibrarySortOrder.dateAdded,
};

String librarySortLabel(AppLocalizations l10n, LibrarySortOrder order) =>
    switch (order) {
      LibrarySortOrder.dateAdded => l10n.librarySortDateImported,
      LibrarySortOrder.lastRead => l10n.librarySortRecentlyRead,
      LibrarySortOrder.alphabetical => l10n.librarySortAlphabetical,
    };

/// Manages the library sort order, persisted via app settings.
class LibrarySortNotifier extends Notifier<LibrarySortOrder> {
  bool _hasLoaded = false;

  @override
  LibrarySortOrder build() => LibrarySortOrder.dateAdded;

  Future<void> loadPersistedSort() async {
    if (_hasLoaded) return;
    _hasLoaded = true;
    final stored = await ref.read(appSettingsStorageProvider).loadSortOrder();
    if (stored != null) state = _sortOrderFromString(stored);
  }

  void setSortOrder(LibrarySortOrder order) {
    state = order;
    unawaited(ref.read(appSettingsStorageProvider).saveSortOrder(order.name));
  }
}

final librarySortProvider =
    NotifierProvider<LibrarySortNotifier, LibrarySortOrder>(
      LibrarySortNotifier.new,
    );

// ──────────────── Collections ────────────────

/// Provider for the collection repository.
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return CollectionRepository(ref.watch(databaseProvider));
});

/// Reactive stream of all collections, ordered by name.
final collectionsProvider = StreamProvider<List<Collection>>((ref) {
  return ref.watch(collectionRepositoryProvider).watchCollections();
});

/// Reactive stream of all book ↔ collection memberships.
final bookCollectionsProvider = StreamProvider<List<BookCollection>>((ref) {
  return ref.watch(collectionRepositoryProvider).watchMemberships();
});

// ──────────────── Books ────────────────

/// Provider for the book repository.
final bookRepositoryProvider = Provider<BookRepository>((ref) {
  return BookRepository(ref.watch(databaseProvider));
});

/// Reactive stream of all books in the library, sorted by the current sort
/// order.
final booksProvider = StreamProvider<List<Book>>((ref) {
  final sortOrder = ref.watch(librarySortProvider);
  final stream = ref.watch(bookRepositoryProvider).watchAllBooks();
  return stream.map((books) {
    switch (sortOrder) {
      case LibrarySortOrder.dateAdded:
        books.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case LibrarySortOrder.lastRead:
        books.sort((a, b) {
          // Books never opened go to the end.
          if (a.lastReadAt == null && b.lastReadAt == null) return 0;
          if (a.lastReadAt == null) return 1;
          if (b.lastReadAt == null) return -1;
          return b.lastReadAt!.compareTo(a.lastReadAt!);
        });
      case LibrarySortOrder.alphabetical:
        books.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return books;
  });
});

/// State for book import progress.
class BookImportState {
  final bool isImporting;
  final double? progress; // null = indeterminate, 0.0–1.0 = determinate
  final String? error;
  final String? successMessage;
  final Book? importedBook;

  /// 1-based index of the file currently importing within a batch.
  /// Only set (along with [batchTotal]) when importing more than one file.
  final int? batchCurrent;
  final int? batchTotal;

  const BookImportState({
    this.isImporting = false,
    this.progress,
    this.error,
    this.successMessage,
    this.importedBook,
    this.batchCurrent,
    this.batchTotal,
  });
}

/// Notifier for managing book import state.
class BookImportNotifier extends Notifier<BookImportState> {
  Timer? _autoDismissTimer;

  @override
  BookImportState build() => const BookImportState();

  void _showSuccess(String message, Book book) {
    _autoDismissTimer?.cancel();
    state = BookImportState(successMessage: message, importedBook: book);
    _autoDismissTimer = Timer(const Duration(seconds: 5), clearState);
  }

  /// Import one or more EPUB ('epub') or CBZ ('cbz') files.
  ///
  /// Individual failures don't abort the batch: remaining files still
  /// import, and a summary error names the files that failed. Returns the
  /// number of successfully imported books.
  Future<int> importFiles(
    List<String> filePaths, {
    required String format,
  }) async {
    if (filePaths.isEmpty) return 0;

    final total = filePaths.length;
    final failures = <String>[];
    Book? lastImported;

    for (var i = 0; i < total; i++) {
      void updateProgress(double? fileProgress) {
        state = BookImportState(
          isImporting: true,
          progress: fileProgress == null && total == 1
              ? null // single EPUB: indeterminate, as before
              : (i + (fileProgress ?? 0)) / total,
          batchCurrent: total > 1 ? i + 1 : null,
          batchTotal: total > 1 ? total : null,
        );
      }

      updateProgress(format == 'cbz' ? 0.0 : null);
      try {
        lastImported = await _importOne(
          filePaths[i],
          format: format,
          onProgress: updateProgress,
        );
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
        failures.add(p.basename(filePaths[i]));
      }
    }

    final succeeded = total - failures.length;
    if (failures.isEmpty) {
      _showSuccess(
        total == 1
            ? '"${lastImported!.title}" added to library!'
            : 'Imported $total books',
        lastImported!,
      );
    } else {
      state = BookImportState(
        error:
            'Imported $succeeded of $total — '
            '${failures.length} failed: ${failures.join(', ')}',
      );
    }
    return succeeded;
  }

  /// Shared per-file import: repository call + pending-backup application
  /// + telemetry. Throws on failure; does not touch [state].
  Future<Book> _importOne(
    String filePath, {
    required String format,
    void Function(double progress)? onProgress,
  }) async {
    final repo = ref.read(bookRepositoryProvider);
    final book = await tracedOperation(
      'book.import_duration_ms',
      action: () => format == 'cbz'
          ? repo.importCbz(filePath, onProgress: onProgress)
          : repo.importEpub(filePath),
      attributes: {'format': format},
    );
    await applyPendingBackupData(book);
    _logBookImported(format);
    return book;
  }

  /// One success log (mirrored to Firebase) plus a counter, so the failure
  /// rate is derivable against tracedOperation's book.import_failed count.
  void _logBookImported(String format) {
    logUsage('book.imported', attrs: {'format': format});
    countUsage('book.imported', attrs: {'format': format});
  }

  Future<Book?> importManga(String filePath, {String? cachedFilePath}) async {
    state = const BookImportState(isImporting: true);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await tracedOperation(
        'book.import_duration_ms',
        action: () => repo.importMangaFromFile(
          filePath,
          cachedFilePath: cachedFilePath,
          safTreeUri: null,
          safSelectedFileRelativePath: null,
        ),
        attributes: {'format': 'manga'},
      );
      await applyPendingBackupData(book);
      _logBookImported('manga');
      _showSuccess('"${book.title}" added to library!', book);
      return book;
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  Future<Book?> importMangaWithSaf(
    String filePath, {
    String? cachedFilePath,
    required String safTreeUri,
    required String? safSelectedFileRelativePath,
  }) async {
    state = const BookImportState(isImporting: true);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await tracedOperation(
        'book.import_duration_ms',
        action: () => repo.importMangaFromFile(
          filePath,
          cachedFilePath: cachedFilePath,
          safTreeUri: safTreeUri,
          safSelectedFileRelativePath: safSelectedFileRelativePath,
        ),
        attributes: {'format': 'manga_saf'},
      );
      await applyPendingBackupData(book);
      _logBookImported('manga_saf');
      _showSuccess('"${book.title}" added to library!', book);
      return book;
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  /// Check for pending backup data matching this book and apply it.
  Future<void> applyPendingBackupData(Book book) async {
    try {
      final pendingRepo = ref.read(pendingBookDataRepositoryProvider);
      final matchService = ref.read(bookMatchServiceProvider);
      final hashKey = await matchService.generateHashKeyForPath(
        book.filePath,
        book.bookType,
      );

      PendingBookData? pending;
      if (hashKey != null) {
        pending = await pendingRepo.findByBookKey(hashKey);
      }

      // Backward compatibility with old title-based backup keys.
      pending ??= await pendingRepo.findByBookKey(
        matchService.generateKey(book.title, book.bookType),
      );

      if (pending != null) {
        final restoreService = ref.read(restoreServiceProvider);
        final entry = BackupSerializer.decodeBookEntry(pending.dataJson);
        await restoreService.applyBookData(book.id, entry);
        await pendingRepo.deleteById(pending.id);
        debugPrint('[Backup] Applied pending data for "${book.title}"');
      }
    } catch (e, st) {
      // Don't let pending data errors block import
      debugPrint('[Backup] Failed to apply pending data: $e');
      Sentry.captureException(e, stackTrace: st);
    }
  }

  void clearState() {
    _autoDismissTimer?.cancel();
    state = const BookImportState();
  }

  Future<void> deleteBook(int bookId) async {
    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await repo.getBookById(bookId);
      await repo.deleteBook(bookId);
      if (book != null) {
        logUsage('library.book_deleted', attrs: {'format': book.bookType});
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      state = BookImportState(error: 'Delete failed: $e');
    }
  }
}

final bookImportProvider =
    NotifierProvider<BookImportNotifier, BookImportState>(
      BookImportNotifier.new,
    );
