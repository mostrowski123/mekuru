import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/atomic_file.dart';

/// epub.js's locations for a book (the positions reading progress counts
/// in), kept in `locations.json` beside its EPUB: generating them loads
/// every section of the book, which a long book makes slow on each open. The
/// file lives in the book's folder, so it goes when the book is deleted and
/// a full backup carries it.
class EpubLocationsCache {
  /// Bump whenever epub.js or the bridge's locations logic changes, so
  /// locations saved before are generated again.
  static const version = 1;

  /// The locations saved for [epubPath] as a JSON array, or null when they
  /// have to be generated: none saved, saved by another [version] or for
  /// another file (size or modification time), or unreadable.
  static Future<String?> read(String epubPath) async {
    try {
      final saved = jsonDecode(await _file(epubPath).readAsString()) as Map;
      final key = await _key(epubPath);
      if (key.entries.any((e) => saved[e.key] != e.value)) return null;
      return jsonEncode(List<String>.from(saved['locations'] as List));
    } catch (_) {
      return null;
    }
  }

  /// Saves [locations], the JSON array epub.js's `locations.save()` returns.
  /// Best effort: a failed write only means generating them next time.
  static Future<void> write(String epubPath, String locations) async {
    try {
      await writeStringAtomic(
        _file(epubPath),
        jsonEncode({
          ...await _key(epubPath),
          'locations': List<String>.from(jsonDecode(locations) as List),
        }),
      );
    } catch (error) {
      debugPrint('[EPUB_LOCATIONS] not saved: $error');
    }
  }

  static File _file(String epubPath) =>
      File(p.join(p.dirname(epubPath), 'locations.json'));

  static Future<Map<String, Object>> _key(String epubPath) async {
    final stat = await File(epubPath).stat();
    return {
      'version': version,
      'size': stat.size,
      'modified': stat.modified.millisecondsSinceEpoch,
    };
  }
}
