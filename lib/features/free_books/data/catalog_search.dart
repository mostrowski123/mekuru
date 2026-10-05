import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

/// Folds text for matching: full-width to ASCII, katakana to hiragana,
/// lower case, no spaces.
String searchKey(String text) =>
    katakanaToHiragana(foldSearchInput(text).toLowerCase().replaceAll(' ', ''));

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
