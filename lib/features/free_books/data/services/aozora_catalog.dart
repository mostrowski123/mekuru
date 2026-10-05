import 'dart:convert';

import 'package:mekuru/features/free_books/data/catalog_search.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';

/// Reading pace for time estimates: a typical learner's, in characters per
/// minute.
const double learnerPaceCharsPerMinute = 250;

/// Parses the bundled `assets/free_books/aozora.json`.
List<AozoraWork> parseAozoraCatalog(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final authors = [
    for (final author in root['authors'] as List)
      (author as List).cast<String>(),
  ];
  return [
    for (final work in root['works'] as List)
      AozoraWork.fromJson(work as Map<String, dynamic>, authors),
  ];
}

/// Reading-time buckets for the length filter.
enum AozoraLength {
  under10Minutes,
  under30Minutes,
  under1Hour,
  under3Hours,
  longer;

  static AozoraLength forMinutes(double minutes) {
    if (minutes <= 10) return under10Minutes;
    if (minutes <= 30) return under30Minutes;
    if (minutes <= 60) return under1Hour;
    if (minutes <= 180) return under3Hours;
    return longer;
  }
}

enum AozoraSort { popular, easiest, hardest, shortest, longest, title, author }

/// Search, filters and sort for the Aozora tab. Empty filter sets mean
/// "any".
class AozoraQuery {
  const AozoraQuery({
    this.text = '',
    this.levels = const {},
    this.lengths = const {},
    this.genres = const {},
    this.spellings = const {},
    this.hideInLibrary = false,
    this.sort = AozoraSort.popular,
  });

  /// The view the tab opens on: the easiest estimated levels in modern
  /// spelling, most-read first.
  static const easyPicks = AozoraQuery(
    levels: {5, 4, 3},
    spellings: {AozoraSpelling.modern},
  );

  final String text;

  /// Estimated JLPT levels (5..1, 0 = beyond N1).
  final Set<int> levels;
  final Set<AozoraLength> lengths;
  final Set<AozoraGenre> genres;
  final Set<AozoraSpelling> spellings;
  final bool hideInLibrary;
  final AozoraSort sort;

  bool get hasFilters =>
      levels.isNotEmpty ||
      lengths.isNotEmpty ||
      genres.isNotEmpty ||
      spellings.isNotEmpty ||
      hideInLibrary;

  AozoraQuery copyWith({
    String? text,
    Set<int>? levels,
    Set<AozoraLength>? lengths,
    Set<AozoraGenre>? genres,
    Set<AozoraSpelling>? spellings,
    bool? hideInLibrary,
    AozoraSort? sort,
  }) => AozoraQuery(
    text: text ?? this.text,
    levels: levels ?? this.levels,
    lengths: lengths ?? this.lengths,
    genres: genres ?? this.genres,
    spellings: spellings ?? this.spellings,
    hideInLibrary: hideInLibrary ?? this.hideInLibrary,
    sort: sort ?? this.sort,
  );

  /// Same search and sort, no filters.
  AozoraQuery cleared() => AozoraQuery(text: text, sort: sort);
}

/// Minutes [work] takes at a typical learner's pace.
double readingMinutes(AozoraWork work) =>
    work.charCount / learnerPaceCharsPerMinute;

/// The works [query] selects, in its sort order. [isInLibrary] answers the
/// hide-in-library filter.
List<AozoraWork> filterAndSortWorks(
  List<AozoraWork> works,
  AozoraQuery query, {
  bool Function(AozoraWork work)? isInLibrary,
}) {
  final needles = searchNeedles(query.text);
  final result = works.where((work) {
    if (query.levels.isNotEmpty && !query.levels.contains(work.jlptEstimate)) {
      return false;
    }
    if (query.genres.isNotEmpty && !query.genres.contains(work.genre)) {
      return false;
    }
    if (query.spellings.isNotEmpty &&
        !query.spellings.contains(work.spelling)) {
      return false;
    }
    if (query.lengths.isNotEmpty &&
        !query.lengths.contains(
          AozoraLength.forMinutes(readingMinutes(work)),
        )) {
      return false;
    }
    if (query.hideInLibrary && (isInLibrary?.call(work) ?? false)) {
      return false;
    }
    if (needles.isNotEmpty && !needles.any(work.searchText.contains)) {
      return false;
    }
    return true;
  }).toList();
  result.sort((a, b) => _compare(query.sort, a, b));
  return result;
}

/// [sort]'s own order, then most-read first, then by id (Dart's sort is not
/// stable, so every tie needs a deterministic breaker).
int _compare(AozoraSort sort, AozoraWork a, AozoraWork b) {
  final first = switch (sort) {
    AozoraSort.popular => 0,
    AozoraSort.easiest => a.difficultyRank.compareTo(b.difficultyRank),
    AozoraSort.hardest => b.difficultyRank.compareTo(a.difficultyRank),
    AozoraSort.shortest => a.charCount.compareTo(b.charCount),
    AozoraSort.longest => b.charCount.compareTo(a.charCount),
    AozoraSort.title => a.titleSortKey.compareTo(b.titleSortKey),
    AozoraSort.author => switch (a.authorSortKey.compareTo(b.authorSortKey)) {
      0 => a.titleSortKey.compareTo(b.titleSortKey),
      final byAuthor => byAuthor,
    },
  };
  if (first != 0) return first;
  final byPopularity = b.popularity.compareTo(a.popularity);
  return byPopularity != 0 ? byPopularity : a.id.compareTo(b.id);
}
