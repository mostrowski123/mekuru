import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// ──────────────── Sort ────────────────

/// Sort orders available in the library.
enum LibrarySortOrder { dateAdded, lastRead, alphabetical }

LibrarySortOrder _sortOrderFromString(String? value) => switch (value) {
  'lastRead' => LibrarySortOrder.lastRead,
  'alphabetical' => LibrarySortOrder.alphabetical,
  _ => LibrarySortOrder.dateAdded,
};

String librarySortLabel(LibrarySortOrder order) => switch (order) {
  LibrarySortOrder.dateAdded => 'Date imported',
  LibrarySortOrder.lastRead => 'Recently read',
  LibrarySortOrder.alphabetical => 'Alphabetical',
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

  const BookImportState({
    this.isImporting = false,
    this.progress,
    this.error,
    this.successMessage,
  });
}

/// Notifier for managing book import state.
class BookImportNotifier extends Notifier<BookImportState> {
  Timer? _autoDismissTimer;

  @override
  BookImportState build() => const BookImportState();

  void _showSuccess(String message) {
    _autoDismissTimer?.cancel();
    state = BookImportState(successMessage: message);
    _autoDismissTimer = Timer(const Duration(seconds: 3), clearState);
  }

  Future<Book?> importEpub(String filePath) async {
    state = const BookImportState(isImporting: true);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await repo.importEpub(filePath);
      Sentry.addBreadcrumb(
        Breadcrumb(message: 'EPUB imported', category: 'library'),
      );
      _showSuccess('"${book.title}" added to library!');
      return book;
    } catch (e) {
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  Future<Book?> importCbz(String filePath) async {
    state = const BookImportState(isImporting: true, progress: 0.0);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await repo.importCbz(
        filePath,
        onProgress: (p) {
          state = BookImportState(isImporting: true, progress: p);
        },
      );
      Sentry.addBreadcrumb(
        Breadcrumb(message: 'CBZ imported', category: 'library'),
      );
      _showSuccess('"${book.title}" added to library!');
      return book;
    } catch (e) {
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  Future<Book?> importManga(String filePath, {String? cachedFilePath}) async {
    state = const BookImportState(isImporting: true);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await repo.importMangaFromFile(
        filePath,
        cachedFilePath: cachedFilePath,
        safTreeUri: null,
        safSelectedFileRelativePath: null,
      );
      Sentry.addBreadcrumb(
        Breadcrumb(message: 'Manga imported', category: 'library'),
      );
      _showSuccess('"${book.title}" added to library!');
      return book;
    } catch (e) {
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
      final book = await repo.importMangaFromFile(
        filePath,
        cachedFilePath: cachedFilePath,
        safTreeUri: safTreeUri,
        safSelectedFileRelativePath: safSelectedFileRelativePath,
      );
      Sentry.addBreadcrumb(
        Breadcrumb(message: 'Manga imported (SAF)', category: 'library'),
      );
      _showSuccess('"${book.title}" added to library!');
      return book;
    } catch (e) {
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  void clearState() {
    _autoDismissTimer?.cancel();
    state = const BookImportState();
  }

  Future<void> deleteBook(int bookId) async {
    try {
      final repo = ref.read(bookRepositoryProvider);
      await repo.deleteBook(bookId);
    } catch (e) {
      state = BookImportState(error: 'Delete failed: $e');
    }
  }
}

final bookImportProvider =
    NotifierProvider<BookImportNotifier, BookImportState>(
      BookImportNotifier.new,
    );
