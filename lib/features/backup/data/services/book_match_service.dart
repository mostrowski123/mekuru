import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:path/path.dart' as p;

/// Generates stable identity keys for books and matches them across backups.
class BookMatchService {
  static const _hashMarker = 'sha256';

  /// Generate a stable identity key for a book.
  ///
  /// Format: `{bookType}::{normalizedTitle}`
  /// Distinguishes an EPUB and a manga with the same title.
  String generateKey(String title, String bookType) {
    final normalizedTitle = title.trim().toLowerCase();
    return '$bookType::$normalizedTitle';
  }

  /// Returns whether [bookKey] is a hash-based key.
  bool isHashKey(String bookKey) {
    return bookKey.contains('::$_hashMarker::');
  }

  /// Build a hash-key index for existing books.
  ///
  /// Books that cannot be hashed are skipped.
  Future<Map<String, Book>> buildHashIndex(List<Book> existingBooks) async {
    final index = <String, Book>{};
    for (final book in existingBooks) {
      final key = await generateHashKeyForPath(book.filePath, book.bookType);
      if (key != null) {
        index[key] = book;
      }
    }
    return index;
  }

  /// Generate the preferred backup key for a book:
  /// hash key when possible, otherwise legacy title key.
  Future<String> generatePreferredKey(
    String title,
    String bookType,
    String filePath,
  ) async {
    final hashKey = await generateHashKeyForPath(filePath, bookType);
    if (hashKey != null) return hashKey;
    return generateKey(title, bookType);
  }

  /// Generates a hash-based key from file or directory content:
  /// `{bookType}::sha256::{digest}`.
  ///
  /// Returns `null` when [filePath] cannot be read.
  Future<String?> generateHashKeyForPath(
    String filePath,
    String bookType,
  ) async {
    final digest = await computeSha256ForPath(filePath);
    if (digest == null) return null;
    return '$bookType::$_hashMarker::$digest';
  }

  /// Computes SHA-256 for a file or directory.
  ///
  /// For directories, hashes all files in recursive relative-path order,
  /// including each relative path in the hash input for determinism.
  Future<String?> computeSha256ForPath(String filePath) async {
    final type = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;

    if (type == FileSystemEntityType.file) {
      final file = File(filePath);
      try {
        final digest = await sha256.bind(file.openRead()).first;
        return digest.toString();
      } catch (_) {
        return null;
      }
    }

    if (type != FileSystemEntityType.directory) return null;

    final dir = Directory(filePath);
    final files = <File>[];
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) files.add(entity);
      }
    } catch (_) {
      return null;
    }

    files.sort(
      (a, b) => p
          .relative(a.path, from: dir.path)
          .compareTo(p.relative(b.path, from: dir.path)),
    );

    final sink = AccumulatorSink<Digest>();
    final converter = sha256.startChunkedConversion(sink);
    try {
      for (final file in files) {
        final relativePath = p
            .relative(file.path, from: dir.path)
            .replaceAll('\\', '/');
        converter.add(utf8.encode(relativePath));
        converter.add([0]);
        await for (final chunk in file.openRead()) {
          converter.add(chunk);
        }
        converter.add([0]);
      }
      converter.close();
      return sink.events.single.toString();
    } catch (_) {
      return null;
    }
  }

  /// Find a matching book in the existing library by legacy title-based key.
  /// Returns the first match, or `null` if no match is found.
  Book? findLegacyMatch(String bookKey, List<Book> existingBooks) {
    for (final book in existingBooks) {
      final existingKey = generateKey(book.title, book.bookType);
      if (existingKey == bookKey) return book;
    }
    return null;
  }
}
