import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/main.dart';

/// Provider for the book repository.
final bookRepositoryProvider = Provider<BookRepository>((ref) {
  return BookRepository(ref.watch(databaseProvider));
});

/// Reactive stream of all books in the library.
final booksProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(bookRepositoryProvider).watchAllBooks();
});

/// State for book import progress.
class BookImportState {
  final bool isImporting;
  final String? error;
  final String? successMessage;

  const BookImportState({
    this.isImporting = false,
    this.error,
    this.successMessage,
  });
}

/// Notifier for managing book import state.
class BookImportNotifier extends Notifier<BookImportState> {
  @override
  BookImportState build() => const BookImportState();

  Future<Book?> importEpub(String filePath) async {
    state = const BookImportState(isImporting: true);

    try {
      final repo = ref.read(bookRepositoryProvider);
      final book = await repo.importEpub(filePath);
      state = BookImportState(
        successMessage: '"${book.title}" added to library!',
      );
      return book;
    } catch (e) {
      state = BookImportState(error: e.toString());
      return null;
    }
  }

  void clearState() {
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
