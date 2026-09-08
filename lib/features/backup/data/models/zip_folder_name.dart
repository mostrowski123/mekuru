import 'dart:convert';

/// Turns a book title into a folder name that unzips cleanly on every
/// desktop: no path separators or characters Windows refuses, no leading
/// or trailing dots and spaces, no reserved device names, and short enough
/// for long nested paths. Falls back to [fallback] (the import directory
/// name) when nothing usable is left.
String zipFolderName(String title, {required String fallback}) {
  var name = title.replaceAll(_illegal, ' ').replaceAll(_spaces, ' ').trim();
  name = _trimEdges(name);
  if (_reserved.hasMatch(name)) name = '_$name';

  final runes = name.runes.toList();
  if (runes.length > _maxChars) {
    name = String.fromCharCodes(runes.take(_maxChars));
  }
  while (utf8.encode(name).length > _maxBytes) {
    final kept = name.runes.toList();
    name = String.fromCharCodes(kept.take(kept.length - 1));
  }
  name = _trimEdges(name);
  return name.isEmpty ? fallback : name;
}

/// Makes [names] unique the way a file manager would, case-insensitively:
/// the first occurrence keeps its name, later ones get ` (2)`, ` (3)`, ...
/// without ever colliding with a name that appears elsewhere in the list.
List<String> dedupeFolderNames(Iterable<String> names) {
  final list = names.toList();
  final originals = {for (final n in list) n.toLowerCase()};
  final emitted = <String>{};
  final result = <String>[];
  for (final name in list) {
    var candidate = name;
    var n = 2;
    while (emitted.contains(candidate.toLowerCase()) ||
        (candidate != name && originals.contains(candidate.toLowerCase()))) {
      candidate = '$name ($n)';
      n++;
    }
    emitted.add(candidate.toLowerCase());
    result.add(candidate);
  }
  return result;
}

const _maxChars = 60;
const _maxBytes = 150;

final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
final _spaces = RegExp(r'\s+');
final _leadingEdge = RegExp(r'^[. ]+');
final _trailingEdge = RegExp(r'[. ]+$');
final _reserved = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
  caseSensitive: false,
);

String _trimEdges(String s) =>
    s.replaceFirst(_leadingEdge, '').replaceFirst(_trailingEdge, '');
