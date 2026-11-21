import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/image_convert.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/core/utils/xhtml.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;

import '../models/mokuro_models.dart';

/// A manga's page images are not in the folder its .mokuro or .html file
/// names: the folder beside it was renamed or left behind (MEKURU-30). The
/// user's files, not a bug, so it files no issue.
class MangaImagesMissingException implements UserSideFailure {
  const MangaImagesMissingException(this.folderName);

  /// The folder the images must be in, next to the .mokuro or .html file.
  final String folderName;

  // Without the folder's name: it is the book's title.
  @override
  String toString() => 'MangaImagesMissingException: image folder not found';
}

/// Parses mokuro HTML files and OCR JSON to produce [MokuroBookManifest]s
/// and [MokuroPage]s.
///
/// On Android, [Directory.list] cannot see files due to scoped storage (SAF)
/// restrictions — only subdirectories are visible. However, [File.exists] and
/// [File.readAsString] work fine for known paths. This parser handles that
/// by extracting image filenames from the mokuro HTML file rather than listing
/// the image directory.
class MokuroParser {
  static String _normalizeSafRelativeDir(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized == '.') return '';
    return normalized;
  }

  static String _joinSafRelative(List<String> parts) {
    final filtered = parts
        .map((s) => s.replaceAll('\\', '/'))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (filtered.isEmpty) return '';
    return p.posix.joinAll(filtered);
  }

  /// A page's image path relative to its image folder, with '/' between
  /// folders: chapter subfolders are kept (`ch1/001.jpg`). A path that is
  /// absolute or climbs out of the folder keeps only its file name.
  static String _pageRelativePath(String path) {
    final relative = p.posix.normalize(path.replaceAll('\\', '/'));
    return p.posix.isAbsolute(relative) ||
            relative == '..' ||
            relative.startsWith('../')
        ? p.posix.basename(relative)
        : relative;
  }

  /// The folder a .mokuro volume's pages are in: the first of [candidates]
  /// that [holdsFirstPage]; otherwise the first that [exists] (a volume
  /// missing its first page). The last candidate is the .mokuro's own folder,
  /// which always exists, so it counts only when it holds the first page.
  /// Null when the pages are in none of them.
  static Future<T?> _imageDir<T>(
    List<T> candidates, {
    required Future<bool> Function(T) holdsFirstPage,
    required Future<bool> Function(T) exists,
  }) async {
    for (final dir in candidates) {
      if (await holdsFirstPage(dir)) return dir;
    }
    for (final dir in candidates.take(candidates.length - 1)) {
      if (await exists(dir)) return dir;
    }
    return null;
  }

  /// Whether the folder the user picked on Android holds the folder
  /// [relativeDir], found the way its pages later are.
  static Future<bool> _safDirExists(String treeUri, String relativeDir) async =>
      await AndroidSafService.getDocumentUriInTree(treeUri, relativeDir) !=
      null;

  /// Logs how much sits beside the book, for diagnosis. Counts only: the
  /// names are the user's other files and folders, and release builds send
  /// this line to Sentry as a breadcrumb.
  static Future<void> _logParentDir(String parentDir) async {
    try {
      final entities = await Directory(parentDir).list().toList();
      final folders = entities.whereType<Directory>().length;
      debugPrint(
        '[MokuroParser] Parent dir holds $folders folders, '
        '${entities.length - folders} files',
      );
    } catch (e) {
      debugPrint('[MokuroParser] Cannot list parent dir: $e');
    }
  }

  /// Parse a single legacy mokuro HTML file.
  ///
  /// Derives the image directory and OCR directory from the HTML file's
  /// location and stem name:
  /// - Image dir: `<parent>/<stem>/`
  /// - OCR dir: `<parent>/_ocr/<stem>/`
  ///
  /// If [originalDirPath] is provided, it is used as the parent directory
  /// for resolving image and OCR paths instead of the HTML file's location.
  /// This supports Android where the file may be read from a cache copy
  /// but image paths must reference the original external storage location.
  ///
  /// Returns a [MokuroBookManifest] and the pre-parsed [MokuroPage] list.
  static Future<(MokuroBookManifest, List<MokuroPage>)> parseSingleHtmlFile(
    String htmlPath, {
    String? originalDirPath,
    String? safTreeUri,
    String? safSelectedFileRelativePath,
  }) async {
    final htmlFile = File(htmlPath);
    if (!await htmlFile.exists()) {
      throw Exception('HTML file not found: $htmlPath');
    }

    final selectedFileName = safSelectedFileRelativePath != null
        ? p.posix.basename(safSelectedFileRelativePath)
        : null;
    var stem = p.basenameWithoutExtension(selectedFileName ?? htmlPath);
    // Strip .mobile suffix — e.g. "BookName.mobile.html" → "BookName"
    if (stem.toLowerCase().endsWith('.mobile')) {
      stem = stem.substring(0, stem.length - '.mobile'.length);
    }
    final parentDir = originalDirPath ?? p.dirname(htmlPath);
    final safParentDirRel = safTreeUri != null
        ? _normalizeSafRelativeDir(
            p.posix.dirname(
              safSelectedFileRelativePath ?? p.basename(htmlPath),
            ),
          )
        : null;

    debugPrint('[MokuroParser] HTML file: $htmlPath');
    if (selectedFileName != null) {
      debugPrint('[MokuroParser] SAF selected file: $selectedFileName');
    }
    debugPrint('[MokuroParser] Stem: $stem, Parent dir: $parentDir');
    await _logParentDir(parentDir);

    // Resolve image directory
    final imageDirPath = p.join(parentDir, stem);
    final safImageDirRel = safTreeUri != null
        ? _joinSafRelative([safParentDirRel ?? '', stem])
        : null;
    debugPrint('[MokuroParser] Image dir: $imageDirPath');
    // When originalDirPath is provided (Android file picker), skip the
    // Directory.exists() check — on Android 13+ without MANAGE_EXTERNAL_STORAGE,
    // directory metadata isn't accessible even though the image files inside
    // ARE readable via READ_MEDIA_IMAGES.
    final imageDirExists = safImageDirRel != null
        ? await _safDirExists(safTreeUri!, safImageDirRel)
        : originalDirPath != null || await Directory(imageDirPath).exists();
    if (!imageDirExists) throw MangaImagesMissingException(stem);

    // Resolve OCR directory
    final ocrDirPath = p.join(parentDir, '_ocr', stem);
    final safOcrDirRel = safTreeUri != null
        ? _joinSafRelative([safParentDirRel ?? '', '_ocr', stem])
        : null;
    debugPrint('[MokuroParser] OCR dir: $ocrDirPath');
    if (originalDirPath == null &&
        safTreeUri == null &&
        !await Directory(ocrDirPath).exists()) {
      throw Exception(
        'OCR folder not found: $ocrDirPath\n'
        'Expected: _ocr/$stem/ in the same directory as the HTML file.',
      );
    }

    // Extract title from HTML
    final title = await _extractTitle(htmlPath, stem);

    // Extract image filenames from HTML
    var imageFiles = await _extractImageFileNamesFromHtml(htmlPath);

    // Fallback: list image directory
    if (imageFiles.isEmpty) {
      debugPrint(
        '[MokuroParser] HTML image extraction failed, '
        'trying dir listing for: $imageDirPath',
      );
      if (safTreeUri != null && safImageDirRel != null) {
        final names = await AndroidSafService.listNamesInTreeDir(
          safTreeUri,
          relativePath: safImageDirRel,
        );
        imageFiles = names.where(CbzParser.isImageFile).toList()
          ..sort(_naturalCompare);
      } else {
        imageFiles = await _listSortedImageFiles(imageDirPath);
      }
    }

    if (imageFiles.isEmpty) {
      throw Exception(
        'No images found for "$stem".\n'
        'Could not extract image names from HTML or list the image folder.',
      );
    }

    debugPrint('[MokuroParser] Parsed "$title" — ${imageFiles.length} pages');

    final manifest = MokuroBookManifest(
      title: title,
      htmlPath: htmlPath,
      imageDirPath: imageDirPath,
      ocrDirPath: ocrDirPath,
      imageFileNames: imageFiles,
      safTreeUri: safTreeUri,
      safImageDirRelativePath: safImageDirRel,
    );

    // Parse OCR pages
    final pages = safTreeUri != null && safOcrDirRel != null
        ? await parseAllPagesSaf(safTreeUri, safOcrDirRel, imageFiles)
        : await parseAllPages(ocrDirPath, imageDirPath, imageFiles);

    return (manifest, pages);
  }

  /// Parse a `.mokuro` JSON file (v0.2+ format).
  ///
  /// The `.mokuro` format embeds all OCR data in a single JSON file with
  /// structure:
  /// ```json
  /// {
  ///   "version": "0.2.4",
  ///   "title": "...",
  ///   "volume": "...",
  ///   "pages": [
  ///     {
  ///       "img_width": 2882,
  ///       "img_height": 4096,
  ///       "blocks": [...],
  ///       "img_path": "0001.jpg"
  ///     }
  ///   ]
  /// }
  /// ```
  ///
  /// The image directory is expected to be a sibling directory with the same
  /// name as the volume (or the mokuro file stem).
  ///
  /// If [originalDirPath] is provided, it is used as the parent directory
  /// for resolving image paths instead of the mokuro file's location.
  ///
  /// Returns a [MokuroBookManifest] and the pre-parsed [MokuroPage] list.
  static Future<(MokuroBookManifest, List<MokuroPage>)> parseMokuroFile(
    String mokuroFilePath, {
    String? originalDirPath,
    String? safTreeUri,
    String? safSelectedFileRelativePath,
  }) async {
    final file = File(mokuroFilePath);
    if (!await file.exists()) {
      throw Exception('Mokuro file not found: $mokuroFilePath');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // On Android [mokuroFilePath] is a temporary copy; the file the user
    // picked is [safSelectedFileRelativePath].
    final fileStem = p.basenameWithoutExtension(
      safSelectedFileRelativePath ?? mokuroFilePath,
    );
    final title =
        (json['title'] as String?) ?? (json['volume'] as String?) ?? fileStem;
    final volume = (json['volume'] as String?) ?? fileStem;

    final parentDir = originalDirPath ?? p.dirname(mokuroFilePath);
    final safParentDirRel = safTreeUri != null
        ? _normalizeSafRelativeDir(
            p.posix.dirname(
              safSelectedFileRelativePath ?? p.basename(mokuroFilePath),
            ),
          )
        : null;

    debugPrint('[MokuroParser] .mokuro file: $mokuroFilePath');
    debugPrint('[MokuroParser] Parent dir: $parentDir');
    debugPrint('[MokuroParser] Title: $title, Volume: $volume');
    await _logParentDir(parentDir);

    // The image folder is a sibling folder named after the volume or the
    // mokuro file's stem, or the parent folder itself (images beside the
    // .mokuro). Chosen after the pages, by where the first page is: img_path
    // is relative to the image folder and may hold chapter subfolders.
    final volumeDirPath = p.join(parentDir, volume);
    final stemDirPath = p.join(parentDir, fileStem);

    final pagesJson = json['pages'] as List;
    final pages = <MokuroPage>[];
    final imageFileNames = <String>[];

    for (int i = 0; i < pagesJson.length; i++) {
      final pageJson = pagesJson[i];
      // Skip structurally unusable page entries instead of failing the
      // whole import — third-party tools emit incomplete .mokuro files.
      if (pageJson is! Map<String, dynamic>) continue;
      final imgPath = pageJson['img_path'];
      final imgWidth = pageJson['img_width'];
      final imgHeight = pageJson['img_height'];
      if (imgPath is! String || imgWidth is! num || imgHeight is! num) {
        continue;
      }
      final imageFileName = _pageRelativePath(imgPath);

      // Skip non-image entries (e.g. .nomedia, .json metadata)
      if (!CbzParser.isImageFile(imageFileName)) continue;

      imageFileNames.add(imageFileName);

      final rawBlocks = pageJson['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks
                .whereType<Map<String, dynamic>>()
                .map(MokuroTextBlock.fromOcrJson)
                .toList()
          : <MokuroTextBlock>[];

      pages.add(
        MokuroPage(
          pageIndex: pages.length,
          imageFileName: imageFileName,
          imgWidth: imgWidth.toInt(),
          imgHeight: imgHeight.toInt(),
          blocks: blocks,
          ocr: MokuroPage.importedOcrState(pageJson),
        ),
      );
    }

    debugPrint('[MokuroParser] Parsed ${pages.length} pages from .mokuro file');

    final firstImage = imageFileNames.firstOrNull;
    var imageDirPath = volumeDirPath;
    String? safImageDirRel;
    if (safTreeUri != null) {
      final volumeRel = _joinSafRelative([safParentDirRel ?? '', volume]);
      final stemRel = _joinSafRelative([safParentDirRel ?? '', fileStem]);
      final parentRel = safParentDirRel ?? '';
      final candidates = <(String rel, String abs)>[
        (volumeRel, volumeDirPath),
        if (volume != fileStem) (stemRel, stemDirPath),
        (parentRel, parentDir),
      ];

      safImageDirRel = volumeRel;
      if (firstImage != null) {
        final found = await _imageDir(
          candidates,
          holdsFirstPage: (dir) => AndroidSafService.existsInTreePath(
            safTreeUri,
            _joinSafRelative([dir.$1, firstImage]),
          ),
          exists: (dir) => _safDirExists(safTreeUri, dir.$1),
        );
        if (found == null) throw MangaImagesMissingException(volume);
        (safImageDirRel, imageDirPath) = found;
      }
    } else if (originalDirPath == null && firstImage != null) {
      final found = await _imageDir(
        [volumeDirPath, if (volume != fileStem) stemDirPath, parentDir],
        holdsFirstPage: (dir) => File(p.join(dir, firstImage)).exists(),
        exists: (dir) => Directory(dir).exists(),
      );
      if (found == null) throw MangaImagesMissingException(volume);
      imageDirPath = found;
    }
    // With originalDirPath (a cached copy of the file), folder metadata may
    // not be readable, so the volume folder is trusted. A volume with no
    // pages is refused later, as having none.
    debugPrint('[MokuroParser] Image dir resolved to: $imageDirPath');

    final manifest = MokuroBookManifest(
      title: title,
      htmlPath: mokuroFilePath, // reuse field for the source file path
      imageDirPath: imageDirPath,
      ocrDirPath: '', // not applicable for .mokuro format
      imageFileNames: imageFileNames,
      safTreeUri: safTreeUri,
      safImageDirRelativePath: safImageDirRel,
    );

    return (manifest, pages);
  }

  /// Extract image filenames from a mokuro HTML file.
  ///
  /// Mokuro embeds page images as CSS `background-image` properties:
  /// ```
  /// background-image:url(&quot;STEM/filename.ext&quot;)
  /// ```
  /// where `&quot;` is the HTML entity for `"` and STEM is URL-encoded.
  ///
  /// This avoids relying on [Directory.list] which fails on Android
  /// scoped storage.
  static Future<List<String>> _extractImageFileNamesFromHtml(
    String htmlPath,
  ) async {
    debugPrint('[MokuroParser] Attempting to read HTML: $htmlPath');
    final htmlFile = File(htmlPath);
    debugPrint(
      '[MokuroParser]   exists=${await htmlFile.exists()}, '
      'path=${htmlFile.path}',
    );
    try {
      final content = await htmlFile.readAsString();
      debugPrint('[MokuroParser]   HTML read OK, length=${content.length}');

      // Match background-image:url("path/to/file.ext") with HTML-encoded
      // or plain quotes. The path may be URL-encoded.
      final regex = RegExp(
        r'background-image:\s*url\((?:&quot;|")(.*?)(?:&quot;|")\)',
      );

      final imageFiles = <String>[];
      for (final match in regex.allMatches(content)) {
        // A path that does not decode is the literal on-disk name.
        final decoded = decodeHref(match.group(1)!);
        // The URL is STEM/<page>, and the image folder is STEM: keep the
        // page's path below it, chapter subfolders included.
        final relative = _pageRelativePath(decoded);
        final slash = relative.indexOf('/');
        imageFiles.add(slash < 0 ? relative : relative.substring(slash + 1));
      }

      // Deduplicate while preserving order, skip non-image files
      final seen = <String>{};
      final unique = <String>[];
      for (final f in imageFiles) {
        if (CbzParser.isImageFile(f) && seen.add(f)) unique.add(f);
      }

      debugPrint(
        '[MokuroParser] Extracted ${unique.length} image filenames from HTML',
      );
      return unique;
    } catch (e) {
      debugPrint('[MokuroParser] Failed to extract images from HTML: $e');
      return [];
    }
  }

  /// Parse a single OCR JSON file into a [MokuroPage].
  static Future<MokuroPage> parseOcrJson(
    String jsonPath,
    int pageIndex,
    String imageFileName,
  ) async {
    final content = await File(jsonPath).readAsString();
    return _parseOcrJsonContent(content, pageIndex, imageFileName);
  }

  static MokuroPage _parseOcrJsonContent(
    String content,
    int pageIndex,
    String imageFileName,
  ) {
    final json = jsonDecode(content) as Map<String, dynamic>;

    final rawBlocks = json['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks
              .whereType<Map<String, dynamic>>()
              .map(MokuroTextBlock.fromOcrJson)
              .toList()
        : <MokuroTextBlock>[];

    return MokuroPage(
      pageIndex: pageIndex,
      imageFileName: imageFileName,
      imgWidth: (json['img_width'] as num).toInt(),
      imgHeight: (json['img_height'] as num).toInt(),
      blocks: blocks,
    );
  }

  static Future<MokuroPage?> parseOcrJsonSaf(
    String treeUri,
    String jsonRelativePath,
    int pageIndex,
    String imageFileName,
  ) async {
    final content = await AndroidSafService.readTextFromTreePath(
      treeUri,
      jsonRelativePath,
    );
    if (content == null) return null;
    try {
      return _parseOcrJsonContent(content, pageIndex, imageFileName);
    } catch (e) {
      debugPrint(
        '[MokuroParser] Failed to parse SAF OCR JSON $jsonRelativePath: $e',
      );
      return null;
    }
  }

  /// Parse all OCR JSON files for a book.
  ///
  /// Matches OCR JSON files to image files by stem name.
  /// Pages without OCR data are included with empty blocks.
  static Future<List<MokuroPage>> parseAllPages(
    String ocrDirPath,
    String imageDirPath,
    List<String> imageFileNames,
  ) async {
    final pages = <MokuroPage>[];

    for (int i = 0; i < imageFileNames.length; i++) {
      final imageFileName = imageFileNames[i];
      // Mirrors the page's subfolders, if any: _ocr/<volume>/ch1/001.json.
      final imageStem = p.posix.withoutExtension(imageFileName);
      final ocrJsonPath = p.join(ocrDirPath, '$imageStem.json');

      if (await File(ocrJsonPath).exists()) {
        pages.add(await parseOcrJson(ocrJsonPath, i, imageFileName));
      } else {
        // No OCR data for this page — include as blank overlay.
        pages.add(
          MokuroPage(
            pageIndex: i,
            imageFileName: imageFileName,
            imgWidth: 0,
            imgHeight: 0,
            blocks: const [],
          ),
        );
      }
    }

    return pages;
  }

  /// Parse all OCR JSON files for a book using an Android SAF tree grant.
  static Future<List<MokuroPage>> parseAllPagesSaf(
    String treeUri,
    String ocrDirRelativePath,
    List<String> imageFileNames,
  ) async {
    final pages = <MokuroPage>[];

    for (int i = 0; i < imageFileNames.length; i++) {
      final imageFileName = imageFileNames[i];
      // Mirrors the page's subfolders, if any: _ocr/<volume>/ch1/001.json.
      final imageStem = p.posix.withoutExtension(imageFileName);
      final ocrJsonRelPath = p.posix.join(
        ocrDirRelativePath,
        '$imageStem.json',
      );

      final parsed = await parseOcrJsonSaf(
        treeUri,
        ocrJsonRelPath,
        i,
        imageFileName,
      );
      if (parsed != null) {
        pages.add(parsed);
      } else {
        // No OCR data for this page — include as blank overlay.
        pages.add(
          MokuroPage(
            pageIndex: i,
            imageFileName: imageFileName,
            imgWidth: 0,
            imgHeight: 0,
            blocks: const [],
          ),
        );
      }
    }

    return pages;
  }

  /// Extract the title from the HTML `<title>` tag, stripping the
  /// ` | mokuro` suffix.
  static Future<String> _extractTitle(
    String htmlPath,
    String fallbackTitle,
  ) async {
    try {
      // Only read the first 2KB to find the <title> tag
      final file = File(htmlPath);
      final raf = await file.open();
      final bytes = await raf.read(2048);
      await raf.close();
      final head = utf8.decode(bytes, allowMalformed: true);

      final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(head);
      if (titleMatch != null) {
        var title = titleMatch.group(1)!;
        // Strip ' | mokuro' suffix
        final mokuroSuffix = ' | mokuro';
        if (title.endsWith(mokuroSuffix)) {
          title = title.substring(0, title.length - mokuroSuffix.length);
        }
        return title.trim();
      }
    } catch (e) {
      debugPrint('[MokuroParser] _extractTitle failed for $htmlPath: $e');
    }
    return fallbackTitle;
  }

  /// List image files in a directory, sorted naturally by name.
  ///
  /// This uses [Directory.list] which works on desktop and iOS but may
  /// return empty results on Android due to scoped storage. Callers should
  /// prefer [_extractImageFileNamesFromHtml] when an HTML file is available.
  static Future<List<String>> _listSortedImageFiles(String dirPath) async {
    final dir = Directory(dirPath);
    final files = <String>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is File && CbzParser.isImageFile(entity.path)) {
          files.add(p.basename(entity.path));
        }
      }
    } catch (e) {
      debugPrint('[MokuroParser] Failed to list images in $dirPath: $e');
      return [];
    }

    // Natural sort: '0.jpg' before '00002.jpg' before '00010.jpg'
    files.sort(_naturalCompare);
    return files;
  }

  /// Natural string comparison that handles embedded numbers.
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

  // ──────────────── Auto-Crop ────────────────

  /// Scans an image to find the bounding rect of non-white content.
  ///
  /// Walks inward from each edge, stopping at the first row/column that
  /// contains a non-white pixel (any RGB channel below [whiteThreshold]).
  /// Returns `null` if the image can't be read or is entirely white.
  static Future<ui.Rect?> computeImageContentBounds(
    String imagePath, {
    double padding = 2.0,
    int whiteThreshold = 240,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      return await computeImageContentBoundsFromBytes(
        bytes,
        padding: padding,
        whiteThreshold: whiteThreshold,
      );
    } catch (e) {
      debugPrint(
        '[MokuroParser] Failed to compute content bounds for $imagePath: $e',
      );
      return null;
    }
  }

  static Future<ui.Rect?> computeImageContentBoundsFromBytes(
    Uint8List bytes, {
    double padding = 2.0,
    int whiteThreshold = 240,
  }) async {
    final codec = await decodeWithAvifFallback(
      bytes,
      () => ui.instantiateImageCodec(bytes),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (byteData == null) return null;

    final pixels = byteData.buffer.asUint8List();
    final thresh = whiteThreshold;
    final top = _findFirstContentRow(
      pixels,
      width: width,
      height: height,
      whiteThreshold: thresh,
    );
    if (top < 0) return null;

    final bottom = _findLastContentRow(
      pixels,
      width: width,
      height: height,
      whiteThreshold: thresh,
      minRow: top,
    );
    final minColumnRun = _minimumColumnRunLength(bottom - top + 1);
    final left = _findFirstContentColumn(
      pixels,
      width: width,
      top: top,
      bottom: bottom,
      whiteThreshold: thresh,
      minRunLength: minColumnRun,
    );
    final right = _findLastContentColumn(
      pixels,
      width: width,
      top: top,
      bottom: bottom,
      whiteThreshold: thresh,
      minColumn: left,
      minRunLength: minColumnRun,
    );
    // Phase 2.5: Content confirmation with stricter threshold.
    // The Phase 2 boundary may sit on light-gray scanning artifacts
    // (pixel values ~190-220) which count as "content" at threshold 240
    // but aren't actual manga ink. Scan inward from the boundary until
    // we find a column with significant "dark" content at a stricter
    // threshold, confirming real ink rather than gray edge artifacts.
    const int darkThreshold = 200; // Pixels must be < 200 in all channels
    final adjLeft = _confirmContentFromLeft(
      pixels,
      width: width,
      top: top,
      bottom: bottom,
      startCol: left,
      rightLimit: right,
      whiteThreshold: thresh,
      darkThreshold: darkThreshold,
    );
    final adjRight = _confirmContentFromRight(
      pixels,
      width: width,
      top: top,
      bottom: bottom,
      startCol: right,
      leftLimit: adjLeft,
      whiteThreshold: thresh,
      darkThreshold: darkThreshold,
    );
    // Phase 2.75: Skip thin panel border lines.
    // Manga panels are framed by thin (2-8px) solid lines that show up as
    // columns with ≥90% dark density at the content boundary. Skip past
    // them to reach the actual artwork inside the panels.
    const double borderLineDensity = 0.90;
    const int maxBorderLinePx = 8;

    int contentLeft = adjLeft;
    for (int dx = 0; dx < maxBorderLinePx; dx++) {
      final x = adjLeft + dx;
      if (x >= adjRight) break;
      final d = _columnDensity(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: darkThreshold,
      );
      if (d < borderLineDensity) break;
      contentLeft = x + 1; // skip past this solid-line column
    }

    int contentRight = adjRight;
    for (int dx = 0; dx < maxBorderLinePx; dx++) {
      final x = adjRight - dx;
      if (x <= contentLeft) break;
      final d = _columnDensity(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: darkThreshold,
      );
      if (d < borderLineDensity) break;
      contentRight = x - 1;
    }

    // Phase 3: Refine top/bottom by re-scanning only within
    // [contentLeft, contentRight] with run-length filtering.
    // This removes page numbers and other isolated horizontal noise that
    // inflated the rough vertical bounds.
    final minRowRun = _minimumRowRunLength(contentRight - contentLeft + 1);
    final refinedTop = _findFirstContentRowFiltered(
      pixels,
      width: width,
      height: height,
      left: contentLeft,
      right: contentRight,
      whiteThreshold: thresh,
      minRunLength: minRowRun,
    );
    int finalTop, finalBottom;
    if (refinedTop >= 0) {
      finalTop = refinedTop;
      finalBottom = _findLastContentRowFiltered(
        pixels,
        width: width,
        height: height,
        left: contentLeft,
        right: contentRight,
        whiteThreshold: thresh,
        minRunLength: minRowRun,
        minRow: refinedTop,
      );
    } else {
      // Filtered scan found nothing (e.g. content narrower than minRowRun);
      // fall back to the original unfiltered bounds.
      finalTop = top;
      finalBottom = bottom;
    }

    // Phase 3.5: Content confirmation for top and bottom rows.
    final adjTop = _confirmContentFromTop(
      pixels,
      width: width,
      left: contentLeft,
      right: contentRight,
      startRow: finalTop,
      bottomLimit: finalBottom,
      whiteThreshold: thresh,
      darkThreshold: darkThreshold,
    );
    final adjBottom = _confirmContentFromBottom(
      pixels,
      width: width,
      left: contentLeft,
      right: contentRight,
      startRow: finalBottom,
      topLimit: adjTop,
      whiteThreshold: thresh,
      darkThreshold: darkThreshold,
    );
    // Phase 3.75: Skip thin horizontal border lines from top and bottom.
    int contentTop = adjTop;
    for (int dy = 0; dy < maxBorderLinePx; dy++) {
      final y = adjTop + dy;
      if (y >= adjBottom) break;
      final d = _rowDensityRange(
        pixels,
        width: width,
        y: y,
        left: contentLeft,
        right: contentRight,
        whiteThreshold: darkThreshold,
      );
      if (d < borderLineDensity) break;
      contentTop = y + 1;
    }

    int contentBottom = adjBottom;
    for (int dy = 0; dy < maxBorderLinePx; dy++) {
      final y = adjBottom - dy;
      if (y <= contentTop) break;
      final d = _rowDensityRange(
        pixels,
        width: width,
        y: y,
        left: contentLeft,
        right: contentRight,
        whiteThreshold: darkThreshold,
      );
      if (d < borderLineDensity) break;
      contentBottom = y - 1;
    }

    final result = ui.Rect.fromLTRB(
      (contentLeft.toDouble() - padding).clamp(0.0, width.toDouble()),
      (contentTop.toDouble() - padding).clamp(0.0, height.toDouble()),
      // +1 because right/bottom are inclusive pixel indices.
      (contentRight.toDouble() + 1 + padding).clamp(0.0, width.toDouble()),
      (contentBottom.toDouble() + 1 + padding).clamp(0.0, height.toDouble()),
    );
    return result;
  }

  /// Fraction of non-white pixels in column [x] between rows [top]–[bottom].
  static double _columnDensity(
    Uint8List pixels, {
    required int width,
    required int x,
    required int top,
    required int bottom,
    required int whiteThreshold,
  }) {
    final totalRows = bottom - top + 1;
    if (totalRows <= 0) return 0.0;
    int count = 0;
    for (int y = top; y <= bottom; y++) {
      final offset = (y * width + x) * 4;
      if (!_isWhitePixel(pixels, offset, whiteThreshold: whiteThreshold)) {
        count++;
      }
    }
    return count / totalRows;
  }

  /// Fraction of non-white pixels in row [y] between columns [left]–[right].
  static double _rowDensityRange(
    Uint8List pixels, {
    required int width,
    required int y,
    required int left,
    required int right,
    required int whiteThreshold,
  }) {
    final totalCols = right - left + 1;
    if (totalCols <= 0) return 0.0;
    int count = 0;
    for (int x = left; x <= right; x++) {
      final offset = (y * width + x) * 4;
      if (!_isWhitePixel(pixels, offset, whiteThreshold: whiteThreshold)) {
        count++;
      }
    }
    return count / totalCols;
  }

  /// Scan rightward from [startCol] until we find a column with significant
  /// density at [darkThreshold] (confirming actual ink, not gray artifacts).
  ///
  /// If the starting column already has >= [minDarkDensity] at [darkThreshold],
  /// it's real content and we return it immediately.
  /// Scans up to [maxScan] columns inward, returning the first column that
  /// meets the dark-density criterion, or [startCol] if none is found.
  static int _confirmContentFromLeft(
    Uint8List pixels, {
    required int width,
    required int top,
    required int bottom,
    required int startCol,
    required int rightLimit,
    required int whiteThreshold,
    required int darkThreshold,
    double minDarkDensity = 0.05,
    int maxScan = 80,
  }) {
    // Check if starting column already has dark content.
    final darkDensity = _columnDensity(
      pixels,
      width: width,
      x: startCol,
      top: top,
      bottom: bottom,
      whiteThreshold: darkThreshold,
    );
    if (darkDensity >= minDarkDensity) return startCol;

    // Starting column is "light gray only" — scan rightward.
    for (int dx = 1; dx <= maxScan; dx++) {
      final x = startCol + dx;
      if (x >= rightLimit) return startCol;
      final d = _columnDensity(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: darkThreshold,
      );
      if (d >= minDarkDensity) return x;
    }
    return startCol;
  }

  /// Mirror of [_confirmContentFromLeft], scanning leftward from the right.
  static int _confirmContentFromRight(
    Uint8List pixels, {
    required int width,
    required int top,
    required int bottom,
    required int startCol,
    required int leftLimit,
    required int whiteThreshold,
    required int darkThreshold,
    double minDarkDensity = 0.05,
    int maxScan = 80,
  }) {
    final darkDensity = _columnDensity(
      pixels,
      width: width,
      x: startCol,
      top: top,
      bottom: bottom,
      whiteThreshold: darkThreshold,
    );
    if (darkDensity >= minDarkDensity) return startCol;

    for (int dx = 1; dx <= maxScan; dx++) {
      final x = startCol - dx;
      if (x <= leftLimit) return startCol;
      final d = _columnDensity(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: darkThreshold,
      );
      if (d >= minDarkDensity) return x;
    }
    return startCol;
  }

  /// Scan downward from [startRow] until we find a row with significant
  /// density at [darkThreshold].
  static int _confirmContentFromTop(
    Uint8List pixels, {
    required int width,
    required int left,
    required int right,
    required int startRow,
    required int bottomLimit,
    required int whiteThreshold,
    required int darkThreshold,
    double minDarkDensity = 0.05,
    int maxScan = 80,
  }) {
    final darkDensity = _rowDensityRange(
      pixels,
      width: width,
      y: startRow,
      left: left,
      right: right,
      whiteThreshold: darkThreshold,
    );
    if (darkDensity >= minDarkDensity) return startRow;

    for (int dy = 1; dy <= maxScan; dy++) {
      final y = startRow + dy;
      if (y >= bottomLimit) return startRow;
      final d = _rowDensityRange(
        pixels,
        width: width,
        y: y,
        left: left,
        right: right,
        whiteThreshold: darkThreshold,
      );
      if (d >= minDarkDensity) return y;
    }
    return startRow;
  }

  /// Mirror of [_confirmContentFromTop], scanning upward from the bottom.
  static int _confirmContentFromBottom(
    Uint8List pixels, {
    required int width,
    required int left,
    required int right,
    required int startRow,
    required int topLimit,
    required int whiteThreshold,
    required int darkThreshold,
    double minDarkDensity = 0.05,
    int maxScan = 80,
  }) {
    final darkDensity = _rowDensityRange(
      pixels,
      width: width,
      y: startRow,
      left: left,
      right: right,
      whiteThreshold: darkThreshold,
    );
    if (darkDensity >= minDarkDensity) return startRow;

    for (int dy = 1; dy <= maxScan; dy++) {
      final y = startRow - dy;
      if (y <= topLimit) return startRow;
      final d = _rowDensityRange(
        pixels,
        width: width,
        y: y,
        left: left,
        right: right,
        whiteThreshold: darkThreshold,
      );
      if (d >= minDarkDensity) return y;
    }
    return startRow;
  }

  static int _findFirstContentRow(
    Uint8List pixels, {
    required int width,
    required int height,
    required int whiteThreshold,
  }) {
    for (int y = 0; y < height; y++) {
      if (_rowHasContent(
        pixels,
        width: width,
        y: y,
        whiteThreshold: whiteThreshold,
      )) {
        return y;
      }
    }
    return -1;
  }

  static int _findLastContentRow(
    Uint8List pixels, {
    required int width,
    required int height,
    required int whiteThreshold,
    required int minRow,
  }) {
    for (int y = height - 1; y >= minRow; y--) {
      if (_rowHasContent(
        pixels,
        width: width,
        y: y,
        whiteThreshold: whiteThreshold,
      )) {
        return y;
      }
    }
    return minRow;
  }

  static int _findFirstContentColumn(
    Uint8List pixels, {
    required int width,
    required int top,
    required int bottom,
    required int whiteThreshold,
    required int minRunLength,
  }) {
    for (int x = 0; x < width; x++) {
      if (_columnHasContent(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: whiteThreshold,
        minRunLength: minRunLength,
      )) {
        return x;
      }
    }
    return 0;
  }

  static int _findLastContentColumn(
    Uint8List pixels, {
    required int width,
    required int top,
    required int bottom,
    required int whiteThreshold,
    required int minColumn,
    required int minRunLength,
  }) {
    for (int x = width - 1; x >= minColumn; x--) {
      if (_columnHasContent(
        pixels,
        width: width,
        x: x,
        top: top,
        bottom: bottom,
        whiteThreshold: whiteThreshold,
        minRunLength: minRunLength,
      )) {
        return x;
      }
    }
    return minColumn;
  }

  static int _minimumColumnRunLength(int contentHeight) =>
      math.max(8, (contentHeight * 0.01).ceil());

  static int _minimumRowRunLength(int contentWidth) =>
      math.max(8, (contentWidth * 0.01).ceil());

  static int _findFirstContentRowFiltered(
    Uint8List pixels, {
    required int width,
    required int height,
    required int left,
    required int right,
    required int whiteThreshold,
    required int minRunLength,
  }) {
    for (int y = 0; y < height; y++) {
      if (_rowHasContentFiltered(
        pixels,
        width: width,
        y: y,
        left: left,
        right: right,
        whiteThreshold: whiteThreshold,
        minRunLength: minRunLength,
      )) {
        return y;
      }
    }
    return -1;
  }

  static int _findLastContentRowFiltered(
    Uint8List pixels, {
    required int width,
    required int height,
    required int left,
    required int right,
    required int whiteThreshold,
    required int minRunLength,
    required int minRow,
  }) {
    for (int y = height - 1; y >= minRow; y--) {
      if (_rowHasContentFiltered(
        pixels,
        width: width,
        y: y,
        left: left,
        right: right,
        whiteThreshold: whiteThreshold,
        minRunLength: minRunLength,
      )) {
        return y;
      }
    }
    return minRow;
  }

  static bool _rowHasContentFiltered(
    Uint8List pixels, {
    required int width,
    required int y,
    required int left,
    required int right,
    required int whiteThreshold,
    required int minRunLength,
  }) {
    int runLength = 0;
    final rowBase = y * width * 4;
    for (int x = left; x <= right; x++) {
      if (!_isWhitePixel(
        pixels,
        rowBase + x * 4,
        whiteThreshold: whiteThreshold,
      )) {
        runLength++;
        if (runLength >= minRunLength) return true;
      } else {
        runLength = 0;
      }
    }
    return false;
  }

  static bool _rowHasContent(
    Uint8List pixels, {
    required int width,
    required int y,
    required int whiteThreshold,
  }) {
    final rowBase = y * width * 4;
    for (int x = 0; x < width; x++) {
      if (!_isWhitePixel(
        pixels,
        rowBase + x * 4,
        whiteThreshold: whiteThreshold,
      )) {
        return true;
      }
    }
    return false;
  }

  static bool _columnHasContent(
    Uint8List pixels, {
    required int width,
    required int x,
    required int top,
    required int bottom,
    required int whiteThreshold,
    required int minRunLength,
  }) {
    int runLength = 0;
    for (int y = top; y <= bottom; y++) {
      final offset = (y * width + x) * 4;
      if (!_isWhitePixel(pixels, offset, whiteThreshold: whiteThreshold)) {
        runLength++;
        if (runLength >= minRunLength) return true;
      } else {
        runLength = 0;
      }
    }
    return false;
  }

  static bool _isWhitePixel(
    Uint8List pixels,
    int offset, {
    required int whiteThreshold,
  }) =>
      pixels[offset] >= whiteThreshold &&
      pixels[offset + 1] >= whiteThreshold &&
      pixels[offset + 2] >= whiteThreshold;

  /// Computes [contentBounds] for all pages by scanning their images.
  static Future<List<MokuroPage>> computeAllContentBounds(
    List<MokuroPage> pages,
    String imageDirPath, {
    int whiteThreshold = 240,
  }) async {
    final result = <MokuroPage>[];
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final imagePath = p.join(imageDirPath, page.imageFileName);
      final bounds = await computeImageContentBounds(
        imagePath,
        whiteThreshold: whiteThreshold,
      );
      result.add(page.copyWith(contentBounds: bounds));
      // Yield to the event loop every 10 pages to keep UI responsive
      if (i % 10 == 9) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    debugPrint(
      '[MokuroParser] Computed content bounds for ${result.length} pages',
    );
    return result;
  }

  /// Computes [contentBounds] for all pages using an Android SAF tree grant.
  static Future<List<MokuroPage>> computeAllContentBoundsSaf(
    List<MokuroPage> pages,
    String safTreeUri,
    String imageDirRelativePath, {
    int whiteThreshold = 240,
  }) async {
    final result = <MokuroPage>[];
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final imageRelPath = _joinSafRelative([
        imageDirRelativePath,
        page.imageFileName,
      ]);

      ui.Rect? bounds;
      try {
        final bytes = await AndroidSafService.readBytesFromTreePath(
          safTreeUri,
          imageRelPath,
        );
        if (bytes != null) {
          bounds = await computeImageContentBoundsFromBytes(
            bytes,
            whiteThreshold: whiteThreshold,
          );
        }
      } catch (e) {
        debugPrint(
          '[MokuroParser] Failed SAF content bounds for $imageRelPath: $e',
        );
      }

      result.add(page.copyWith(contentBounds: bounds));
      if (i % 10 == 9) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    debugPrint(
      '[MokuroParser] Computed SAF content bounds for ${result.length} pages',
    );
    return result;
  }
}
