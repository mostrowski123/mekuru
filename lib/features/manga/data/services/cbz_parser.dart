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

  /// Page dimensions keyed by the extracted filename, read from image headers
  /// during extraction. Pages whose header could not be parsed are absent.
  final Map<String, ImageDimensions> imageDimensions;

  const CbzMetadata({
    required this.title,
    required this.imageDirPath,
    required this.imageFileNames,
    this.coverImagePath,
    this.imageDimensions = const {},
  });

  /// Dimensions for [imageFileName], or null if its header was unreadable.
  ImageDimensions? dimensionsOf(String imageFileName) =>
      imageDimensions[imageFileName];
}

/// Image dimensions read from file headers without full decode.
class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
}

/// Reads an image's pixel dimensions straight out of its header bytes.
///
/// JPEG and PNG — effectively every page in a manga archive — are parsed
/// directly, because `image`'s own `startDecode` is not a header read for
/// JPEG: it walks the frame and allocates the full coefficient buffer, which
/// measures ~31ms on a single 1600x2300 page and scales with pixel count, not
/// file size. A direct SOF read is ~2µs. Other formats fall back to the
/// package decoder, which is correct and rare enough not to matter.
///
/// Returns null for bytes that carry no readable header rather than throwing.
ImageDimensions? readImageDimensionsFromBytes(Uint8List bytes) {
  try {
    return _jpegDimensions(bytes) ??
        _pngDimensions(bytes) ??
        _fallbackDimensions(bytes);
  } catch (e) {
    debugPrint('[CbzParser] Failed to read image dimensions: $e');
    return null;
  }
}

/// JPEG: walk the marker segments to the frame header (SOF0-SOF15, excluding
/// the DHT/JPG/DAC markers that share the range) and read its size fields.
ImageDimensions? _jpegDimensions(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    // Padding and standalone markers carry no length field.
    if (marker == 0xFF ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD8)) {
      i += marker == 0xFF ? 1 : 2;
      continue;
    }
    if (marker == 0xDA) return null; // start of scan: no frame header found
    final isFrameHeader =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrameHeader) {
      final height = (b[i + 5] << 8) | b[i + 6];
      final width = (b[i + 7] << 8) | b[i + 8];
      return width > 0 && height > 0 ? ImageDimensions(width, height) : null;
    }
    final segmentLength = (b[i + 2] << 8) | b[i + 3];
    if (segmentLength < 2) return null; // malformed; refuse to loop forever
    i += 2 + segmentLength;
  }
  return null;
}

/// PNG: the IHDR chunk is fixed at offset 16, immediately after the 8-byte
/// signature and the chunk's own length/type fields.
ImageDimensions? _pngDimensions(Uint8List b) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (b[i] != signature[i]) return null;
  }
  final width = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
  final height = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
  return width > 0 && height > 0 ? ImageDimensions(width, height) : null;
}

ImageDimensions? _fallbackDimensions(Uint8List bytes) {
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) return null;
  return ImageDimensions(info.width, info.height);
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
  static Future<CbzMetadata> extract(
    String cbzPath,
    String outputDir, {
    void Function(double progress)? onProgress,
  }) async {
    final title = p.basenameWithoutExtension(cbzPath);
    final imageDir = Directory(p.join(outputDir, 'images'));
    await imageDir.create(recursive: true);

    // Read and decode the ZIP archive
    final bytes = await File(cbzPath).readAsBytes();
    final archive = await compute(_decodeArchive, bytes);

    // Pre-filter to image files so we can report accurate progress.
    final imageFiles = archive
        .where(
          (f) =>
              f.isFile &&
              !p.basename(f.name).startsWith('.') &&
              _isImageFile(p.basename(f.name)),
        )
        .toList();
    final total = imageFiles.length;

    final imageFileNames = <String>[];
    final usedOutputNames = <String>{};
    final imageDimensions = <String, ImageDimensions>{};
    var written = 0;

    for (final file in imageFiles) {
      final fileName = p.basename(file.name);

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

      // The decompressed bytes are already in hand, so take the page size now
      // rather than reading every page back off disk after extraction.
      final dimensions = readImageDimensionsFromBytes(
        data is Uint8List ? data : Uint8List.fromList(data),
      );
      if (dimensions != null) {
        imageDimensions[outputName] = dimensions;
      }

      written++;
      onProgress?.call(total > 0 ? written / total : 1.0);
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
      imageDimensions: imageDimensions,
    );
  }

  // ── Private helpers ──

  static Archive _decodeArchive(Uint8List bytes) {
    return ZipDecoder().decodeBytes(bytes);
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
