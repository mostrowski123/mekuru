import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the actual `.epub` file path for reader opening.
class EpubFileResolver {
  Future<String> resolveLocalEpubPath(String storedPath) async {
    final entityType = await FileSystemEntity.type(storedPath);

    if (entityType == FileSystemEntityType.file && _isEpubFile(storedPath)) {
      return storedPath;
    }

    if (entityType == FileSystemEntityType.directory) {
      final directory = Directory(storedPath);

      final fromDirectory = await _findFirstEpubFile(directory);
      if (fromDirectory != null) {
        return fromDirectory;
      }

      final fromParent = await _findFirstEpubFile(directory.parent);
      if (fromParent != null) {
        return fromParent;
      }

      throw FileSystemException('No EPUB file found for directory', storedPath);
    }

    throw FileSystemException('Reader path is not a readable EPUB file', storedPath);
  }

  Future<String?> _findFirstEpubFile(Directory directory) async {
    if (!await directory.exists()) {
      return null;
    }

    final files = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final filePath = entity.path;
      if (_isEpubFile(filePath)) {
        files.add(filePath);
      }
    }

    if (files.isEmpty) {
      return null;
    }

    files.sort();
    return files.first;
  }

  bool _isEpubFile(String filePath) {
    return p.extension(filePath).toLowerCase() == '.epub';
  }
}
