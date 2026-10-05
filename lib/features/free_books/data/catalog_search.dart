import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

/// Folds text for matching: full-width to ASCII, katakana to hiragana,
/// lower case, no spaces.
String searchKey(String text) =>
    katakanaToHiragana(foldSearchInput(text).toLowerCase().replaceAll(' ', ''));

/// What a catalog entry's search matches against: each of [fields] folded
/// with [searchKey], kept apart by line breaks, which a query from the
/// single-line search field never holds, so it never matches across two
/// fields (the end of a title and the start of its author's name).
String searchFields(Iterable<String> fields) =>
    fields.map(searchKey).join('\n');

/// What a search query matches: the folded query itself and, when it is
/// romaji ("dazai"), its hiragana so it can match the catalog's readings.
List<String> searchNeedles(String query) {
  final folded = searchKey(query);
  if (folded.isEmpty) return const [];
  return [
    folded,
    if (RomajiConverter.isRomaji(folded)) RomajiConverter.convert(folded),
  ];
}
