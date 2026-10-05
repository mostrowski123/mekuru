import 'dart:convert';

import 'package:mekuru/features/free_books/data/catalog_search.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';

/// Parses the bundled `assets/free_books/tadoku.json` (level, then newest).
List<TadokuBook> parseTadokuCatalog(String json) => [
  for (final book
      in (jsonDecode(json) as Map<String, dynamic>)['books'] as List)
    TadokuBook.fromJson(book as Map<String, dynamic>),
];

/// Search and filters on the Graded readers tab.
class TadokuQuery {
  const TadokuQuery({
    this.text = '',
    this.levels = const {},
    this.hideInLibrary = false,
  });

  final String text;

  /// Tadoku levels (-1 for Start); empty means all.
  final Set<int> levels;
  final bool hideInLibrary;

  TadokuQuery copyWith({String? text, Set<int>? levels, bool? hideInLibrary}) =>
      TadokuQuery(
        text: text ?? this.text,
        levels: levels ?? this.levels,
        hideInLibrary: hideInLibrary ?? this.hideInLibrary,
      );
}

/// The books [query] selects, in catalog order. [isInLibrary] answers
/// hide-in-library.
List<TadokuBook> filterTadokuBooks(
  List<TadokuBook> books,
  TadokuQuery query, {
  bool Function(TadokuBook book)? isInLibrary,
}) {
  final needles = searchNeedles(query.text);
  return [
    for (final book in books)
      if ((query.levels.isEmpty || query.levels.contains(book.level)) &&
          (needles.isEmpty || needles.any(book.searchText.contains)) &&
          !(query.hideInLibrary && (isInLibrary?.call(book) ?? false)))
        book,
  ];
}
