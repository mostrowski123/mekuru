import 'package:mekuru/features/free_books/data/catalog_search.dart';

/// Where every Aozora card page and XHTML file lives; catalog paths are
/// relative to this.
const aozoraCardsBase = 'https://www.aozora.gr.jp/cards/';

/// Genre buckets derived from Aozora's library classification (NDC). The
/// catalog builder (`tools/build_aozora_catalog.py`) writes the codes.
enum AozoraGenre {
  fiction('fic'),
  children('kid'),
  poetry('poe'),
  plays('pla'),
  essays('ess'),
  diaries('dia'),
  history('his'),
  philosophy('phi'),
  nonfiction('non'),
  other('oth');

  const AozoraGenre(this.code);

  final String code;

  static AozoraGenre fromCode(String code) =>
      values.firstWhere((g) => g.code == code);
}

/// Orthography of the edition Aozora transcribed. Pre-war spelling is much
/// harder for learners than the kanji level alone suggests.
enum AozoraSpelling {
  /// Modern kanji and kana.
  modern('m'),

  /// Modern kanji, pre-war kana.
  oldKana('k'),

  /// Pre-war kanji forms (with old or new kana).
  oldKanji('j'),
  other('x');

  const AozoraSpelling(this.code);

  final String code;

  static AozoraSpelling fromCode(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// One work in the bundled Aozora Bunko catalog.
class AozoraWork {
  AozoraWork({
    required this.id,
    required this.title,
    this.subtitle,
    required this.titleReading,
    required this.author,
    required this.authorReading,
    required this.xhtmlPath,
    required this.genre,
    required this.spelling,
    required this.charCount,
    required this.jlptEstimate,
    required this.popularity,
  }) : searchText = searchKey(
         '$title ${subtitle ?? ''} $titleReading $author $authorReading',
       ),
       titleSortKey = searchKey(titleReading),
       authorSortKey = searchKey(authorReading);

  /// [authors] is the catalog's shared `[name, reading]` table that the
  /// entry's `a` indexes. The catalog ships with the app, so a malformed
  /// entry fails loudly (and in the bundled-catalog test) rather than being
  /// papered over.
  factory AozoraWork.fromJson(
    Map<String, dynamic> json,
    List<List<String>> authors,
  ) {
    final author = authors[json['a'] as int];
    return AozoraWork(
      id: json['i'] as int,
      title: json['t'] as String,
      subtitle: json['s'] as String?,
      titleReading: json['r'] as String,
      author: author[0],
      authorReading: author[1],
      xhtmlPath: json['x'] as String,
      genre: AozoraGenre.fromCode(json['g'] as String),
      spelling: AozoraSpelling.fromCode(json['o'] as String),
      charCount: json['n'] as int,
      jlptEstimate: json['l'] as int,
      popularity: json['p'] as int,
    );
  }

  final int id;
  final String title;
  final String? subtitle;
  final String titleReading;
  final String author;
  final String authorReading;

  /// XHTML path below [aozoraCardsBase], e.g. `000035/files/1567_14913.html`.
  final String xhtmlPath;
  final AozoraGenre genre;
  final AozoraSpelling spelling;

  /// Characters in the body text, without whitespace.
  final int charCount;

  /// Estimated JLPT level from the kanji and sentence length: 5 (N5,
  /// easiest) … 1 (N1); 0 means beyond N1. Only an estimate.
  final int jlptEstimate;

  /// Reads summed over Aozora's 2009–2022 access rankings; 0 when unranked.
  final int popularity;

  /// Title as listed and as written into the EPUB: title plus subtitle, so
  /// the parts of a multi-part work stay distinct in the library.
  String get displayTitle => subtitle == null ? title : '$title $subtitle';

  /// The card page always sits beside the XHTML's folder
  /// (`000035/card1567.html`); the catalog builder checks this.
  Uri get cardUrl =>
      Uri.parse('$aozoraCardsBase${xhtmlPath.split('/').first}/card$id.html');

  /// Difficulty rank for sorting: 1 (~N5) … 5 (~N1), 6 beyond N1.
  int get difficultyRank => jlptEstimate == 0 ? 6 : 6 - jlptEstimate;

  // The folded keys are built with the work, so parsing the catalog in an
  // isolate builds them there instead of on the first keystroke.

  /// Everything search matches against, folded like [searchNeedles].
  final String searchText;

  /// Title reading folded to hiragana, for kana-order sorting.
  final String titleSortKey;

  /// Author reading folded to hiragana, for kana-order sorting.
  final String authorSortKey;
}
