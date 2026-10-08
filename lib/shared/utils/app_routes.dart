import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
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

/// Opens whichever reader matches the book's type, at [initialCfi] if given.
/// The route is restorable: when the system kills Mekuru in the background,
/// coming back reopens the book at its saved place.
void openBookReader(NavigatorState navigator, Book book, {String? initialCfi}) {
  _openingReader = _readerFor(book, initialCfi: initialCfi);
  try {
    navigator.restorablePushNamed(
      book.bookType == 'manga' ? 'manga_reader' : 'reader',
      arguments: book.id,
    );
  } finally {
    _openingReader = null;
  }
}

/// The reader [openBookReader] is pushing. The navigator builds the route
/// inside the push, so a live open needs no second read of the book.
Widget? _openingReader;

/// The app navigator's `onGenerateRoute`: builds the readers [openBookReader]
/// pushes, and rebuilds one from its book id when the navigator restores it.
/// They are pushed by name, not with `restorablePush`, whose callback handles
/// resolve through a file iOS may purge from Caches; restoring then throws.
Route<void>? onGenerateAppRoute(RouteSettings settings) {
  final name = settings.name;
  if (name != 'reader' && name != 'manga_reader') return null;
  final reader =
      _openingReader ?? _RestoredBookReader(settings.arguments! as int);
  return namedRoute<void>(name!, (_) => reader);
}

Widget _readerFor(Book book, {String? initialCfi}) => book.bookType == 'manga'
    ? MangaReaderScreen(book: book)
    : ReaderScreen(book: book, initialCfi: initialCfi);

/// A reader the navigator restored: the book is read again (with the place
/// saved when the app went to the background), and the route closes if the
/// book was deleted in the meantime.
class _RestoredBookReader extends ConsumerStatefulWidget {
  const _RestoredBookReader(this.bookId);

  final int bookId;

  @override
  ConsumerState<_RestoredBookReader> createState() =>
      _RestoredBookReaderState();
}

class _RestoredBookReaderState extends ConsumerState<_RestoredBookReader> {
  Book? _book;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final book = await ref
        .read(bookRepositoryProvider)
        .getBookById(widget.bookId);
    if (!mounted) return;
    if (book == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _book = book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return book == null ? const Scaffold() : _readerFor(book);
  }
}
