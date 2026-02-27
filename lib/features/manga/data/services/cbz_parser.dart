import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Metadata extracted from a CBZ archive.
class CbzMetadata {
  /// Title derived from the CBZ filename (sans extension).
  final String title;

  /// Directory where images were extracted.
  final String imageDirPath;

  /// Sorted list of image filenames (basename only).
  final List<String> imageFileNames;

  /// Path to the cover image (first image by natural sort).
  final String? coverImagePath;

  const CbzMetadata({
    required this.title,
    required this.imageDirPath,
    required this.imageFileNames,
    this.coverImagePath,
  });
}

/// Image dimensions read from file headers without full decode.
class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
}

/// Parses CBZ (Comic Book ZIP) archives into sorted image collections.
///
/// CBZ files are standard ZIP archives containing image files (.jpg, .png, etc).
/// This parser extracts the images, sorts them naturally by filename, and
/// provides metadata compatible with the manga reader.
class CbzParser {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.tiff',
    '.tif',
  };

  /// Extract a CBZ archive to [outputDir] and return metadata.
  ///
  /// Images are extracted to `[outputDir]/images/`. Files nested in
  /// subdirectories within the archive are flattened into the images folder.
  /// Non-image files (e.g., metadata XML, thumbs.db) are skipped.
  static Future<CbzMetadata> extract(String cbzPath, String outputDir) async {
    final title = p.basenameWithoutExtension(cbzPath);
    final imageDir = Directory(p.join(outputDir, 'images'));
    await imageDir.create(recursive: true);

    // Read and decode the ZIP archive
    final bytes = await File(cbzPath).readAsBytes();
    final archive = await compute(_decodeArchive, bytes);

    final imageFileNames = <String>[];
    final usedOutputNames = <String>{};

    for (final file in archive) {
      if (file.isFile) {
        final fileName = p.basename(file.name);

        // Skip hidden files and non-image files
        if (fileName.startsWith('.')) continue;
        if (!_isImageFile(fileName)) continue;

        // Handle duplicate filenames from nested dirs by prefixing
        var outputName = fileName;
        if (usedOutputNames.contains(outputName)) {
          final parentDir = p.basename(p.dirname(file.name));
          final stem = p.basenameWithoutExtension(fileName);
          final ext = p.extension(fileName);
          final prefix = (parentDir.isNotEmpty && parentDir != '.')
              ? '${parentDir}_'
              : '';
          final baseName = '$prefix$stem';
          outputName = '$baseName$ext';

          var suffix = 2;
          while (usedOutputNames.contains(outputName)) {
            outputName = '${baseName}_$suffix$ext';
            suffix++;
          }
        }

        final outputPath = p.join(imageDir.path, outputName);
        final data = file.content as List<int>;
        await File(outputPath).writeAsBytes(data);
        imageFileNames.add(outputName);
        usedOutputNames.add(outputName);
      }
    }

    // Natural sort (same algorithm as MokuroParser)
    imageFileNames.sort(_naturalCompare);

    // Cover is the first image
    final coverImagePath = imageFileNames.isNotEmpty
        ? p.join(imageDir.path, imageFileNames.first)
        : null;

    debugPrint(
      '[CbzParser] Extracted ${imageFileNames.length} images from "$title"',
    );

    return CbzMetadata(
      title: title,
      imageDirPath: imageDir.path,
      imageFileNames: imageFileNames,
      coverImagePath: coverImagePath,
    );
  }

  /// Read image dimensions from a file without fully decoding the image.
  ///
  /// Uses the `image` package's decoder to read just the header info.
  /// Returns null if the image cannot be read.
  static Future<ImageDimensions?> readImageDimensions(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      return await compute(_decodeImageDimensions, bytes);
    } catch (e) {
      debugPrint('[CbzParser] Failed to read dimensions for $imagePath: $e');
      return null;
    }
  }

  // ── Private helpers ──

  static Archive _decodeArchive(Uint8List bytes) {
    return ZipDecoder().decodeBytes(bytes);
  }

  static ImageDimensions? _decodeImageDimensions(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return ImageDimensions(image.width, image.height);
  }

  static bool _isImageFile(String fileName) =>
      _imageExtensions.contains(p.extension(fileName).toLowerCase());

  /// Natural string comparison that handles embedded numbers.
  /// Matches the algorithm in MokuroParser for consistency.
  static int _naturalCompare(String a, String b) {
    final aSegments = _splitNumeric(a);
    final bSegments = _splitNumeric(b);
    final len = aSegments.length < bSegments.length
        ? aSegments.length
        : bSegments.length;

    for (var i = 0; i < len; i++) {
      final aNum = int.tryParse(aSegments[i]);
      final bNum = int.tryParse(bSegments[i]);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aSegments[i].compareTo(bSegments[i]);
        if (cmp != 0) return cmp;
      }
    }
    return aSegments.length.compareTo(bSegments.length);
  }

  static List<String> _splitNumeric(String s) {
    return RegExp(r'(\d+|\D+)').allMatches(s).map((m) => m.group(0)!).toList();
  }
}
