import 'package:flutter/material.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';

/// The one way to push a screen. A route without a static name is invisible
/// to Sentry (screen transactions, navigation breadcrumbs) and to Firebase
/// (`screen_view`), so `MaterialPageRoute` is not used directly anywhere
/// else — test/shared/app_routes_test.dart enforces that. Names are stable
/// telemetry ids in snake_case, never titles or user content.
Route<T> namedRoute<T>(String name, WidgetBuilder builder) =>
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name),
      builder: builder,
    );

/// Opens whichever reader matches the book's type.
Route<void> bookReaderRoute(Book book) {
  final isManga = book.bookType == 'manga';
  return namedRoute<void>(
    isManga ? 'manga_reader' : 'reader',
    (_) => isManga ? MangaReaderScreen(book: book) : ReaderScreen(book: book),
  );
}
