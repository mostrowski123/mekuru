/// Pure helpers for converting a prefix term into an index-friendly SQL
/// range. Flutter-free so they stay unit-testable.
///
/// SQLite's LIKE optimization cannot use ordinary BINARY indexes while
/// `case_sensitive_like` is OFF (the default), so `expression LIKE 'あ%'`
/// scans the whole dictionary_entries table. The equivalent range condition
/// `expression >= 'あ' AND expression < prefixUpperBound('あ')` hits
/// idx_expression instead. SQLite compares TEXT as UTF-8 bytes, which orders
/// strings by code point — so the bound is computed on code points, not
/// UTF-16 code units.
library;

/// Smallest string that sorts strictly above every string starting with
/// [prefix] under code-point order: the prefix with its last code point
/// incremented, skipping the surrogate gap (U+D7FF + 1 → U+E000). A trailing
/// U+10FFFF cannot be incremented, so it is dropped and the increment moves
/// to the previous code point. Returns null when no bound exists (empty
/// prefix, or every code point is U+10FFFF).
String? prefixUpperBound(String prefix) {
  final runes = prefix.runes.toList();
  for (var i = runes.length - 1; i >= 0; i--) {
    var next = runes[i] + 1;
    if (next == 0xD800) next = 0xE000;
    if (next <= 0x10FFFF) {
      return String.fromCharCodes([...runes.sublist(0, i), next]);
    }
  }
  return null;
}

final _asciiLetterPattern = RegExp('[a-zA-Z]');

/// Case variants of [term] for prefix matching: as-typed, lowercase,
/// UPPERCASE, and Capitalized. BINARY range scans are case-sensitive, so
/// these preserve the practical part of LIKE's ASCII case-insensitivity
/// ("dvd" finding "DVD") at the cost of a few extra index probes. Terms
/// without ASCII letters are returned as-is.
List<String> prefixSearchVariants(String term) {
  if (term.isEmpty || !_asciiLetterPattern.hasMatch(term)) {
    return [term];
  }
  final lower = term.toLowerCase();
  final capitalized = lower[0].toUpperCase() + lower.substring(1);
  return {term, lower, term.toUpperCase(), capitalized}.toList();
}
