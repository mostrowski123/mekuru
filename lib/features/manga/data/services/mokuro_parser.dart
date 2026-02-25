import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/mokuro_models.dart';

/// Parses mokuro HTML files and OCR JSON to produce [MokuroBookManifest]s
/// and [MokuroPage]s.
///
/// On Android, [Directory.list] cannot see files due to scoped storage (SAF)
/// restrictions — only subdirectories are visible. However, [File.exists] and
/// [File.readAsString] work fine for known paths. This parser handles that
/// by extracting image filenames from the mokuro HTML file rather than listing
/// the image directory.
class MokuroParser {
  /// Discover all mokuro books in a directory.
  ///
  /// Uses a three-pass discovery strategy:
  /// 1. Try to find `.html` files via directory listing
  /// 2. If no files are visible (common on Android due to scoped storage),
  ///    infer book names from visible subdirectories and probe for HTML files
  /// 3. If HTML files are still not accessible, discover books purely from
  ///    directory structure by probing for OCR JSON files
  ///
  /// Returns a list of manifests for valid books.
  /// Throws a descriptive [Exception] if no books are found.
  static Future<List<MokuroBookManifest>> parseMokuroDirectory(
    String dirPath,
  ) async {
    final dir = Directory(dirPath);

    debugPrint('[MokuroParser] Scanning directory: $dirPath');

    List<FileSystemEntity> entities;
    try {
      entities = await dir.list().toList();
    } catch (e) {
      throw Exception('Cannot read directory: $dirPath\n$e');
    }

    debugPrint('[MokuroParser] Found ${entities.length} entities');

    // Separate files and directories from the listing
    final listedFiles = <File>[];
    final listedDirs = <Directory>[];
    for (final entity in entities) {
      if (entity is File) {
        listedFiles.add(entity);
      } else if (entity is Directory) {
        listedDirs.add(entity);
      }
    }

    // Build directory basename → full path map
    final dirsByName = <String, String>{};
    for (final d in listedDirs) {
      dirsByName[p.basename(d.path)] = d.path;
    }

    debugPrint('[MokuroParser] Listed files: ${listedFiles.length}, '
        'dirs: ${listedDirs.length}');
    debugPrint('[MokuroParser] Dir names: ${dirsByName.keys.toList()}');

    // Check for _ocr directory
    final ocrBasePath = dirsByName['_ocr'];
    if (ocrBasePath == null) {
      throw Exception(
        'No _ocr folder found in the selected directory.\n'
        'Found directories: ${dirsByName.keys.join(", ")}\n'
        'Expected: an _ocr/ folder containing per-book OCR JSON subfolders.',
      );
    }

    // List _ocr subdirectories for matching
    final ocrSubDirs = <String, String>{};
    try {
      await for (final entity in Directory(ocrBasePath).list()) {
        if (entity is Directory) {
          ocrSubDirs[p.basename(entity.path)] = entity.path;
        }
      }
    } catch (e) {
      throw Exception('Cannot read _ocr directory: $ocrBasePath\n$e');
    }

    debugPrint('[MokuroParser] _ocr subdirs: ${ocrSubDirs.keys.toList()}');

    // ── Pass 1: Find HTML files from directory listing ──
    var htmlFiles = listedFiles
        .where((f) =>
            f.path.endsWith('.html') && !f.path.endsWith('.mobile.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    debugPrint('[MokuroParser] HTML files from listing: ${htmlFiles.length}');

    // ── Pass 2: If no files were listed (Android scoped storage),
    //    infer from subdirectory names and probe for HTML files ──
    if (htmlFiles.isEmpty && dirsByName.length > 1) {
      debugPrint('[MokuroParser] No files in listing — probing by dir names');
      final probed = <File>[];
      for (final name in dirsByName.keys) {
        if (name == '_ocr') continue;
        // Construct the expected HTML path and check if it exists
        final htmlPath = p.join(dirPath, '$name.html');
        final htmlFile = File(htmlPath);
        if (await htmlFile.exists()) {
          debugPrint('[MokuroParser]   Found: $name.html');
          probed.add(htmlFile);
        } else {
          debugPrint('[MokuroParser]   Not found: $name.html');
        }
      }
      htmlFiles = probed..sort((a, b) => a.path.compareTo(b.path));
    }

    // ── Pass 3: If HTML files still not accessible, discover books
    //    purely from directory structure (no HTML needed) ──
    if (htmlFiles.isEmpty) {
      debugPrint('[MokuroParser] HTML files not accessible — '
          'discovering from directory structure only');
      return _discoverFromDirectories(
        dirPath, dirsByName, ocrSubDirs,
      );
    }

    // ── Process discovered HTML files ──
    final manifests = <MokuroBookManifest>[];
    final skipReasons = <String>[];

    for (final htmlFile in htmlFiles) {
      final stem = p.basenameWithoutExtension(htmlFile.path);
      debugPrint('[MokuroParser] Processing: $stem');

      // Look up image directory by name match
      final imageDirPath = dirsByName[stem];
      if (imageDirPath == null) {
        final reason = '  "$stem": no matching image folder';
        debugPrint('[MokuroParser] SKIP $reason');
        skipReasons.add(reason);
        continue;
      }

      // Look up OCR directory by name match
      final ocrDirPath = ocrSubDirs[stem];
      if (ocrDirPath == null) {
        final reason = '  "$stem": no matching _ocr subfolder';
        debugPrint('[MokuroParser] SKIP $reason');
        skipReasons.add(reason);
        continue;
      }

      // Extract title from HTML <title> tag
      final title = await _extractTitle(htmlFile.path, stem);

      // Extract image filenames from the HTML file.
      // This is the primary method — works on Android where dir.list()
      // cannot see files due to scoped storage restrictions.
      var imageFiles = await _extractImageFileNamesFromHtml(htmlFile.path);

      // Fallback: try directory listing (works on desktop/iOS)
      if (imageFiles.isEmpty) {
        debugPrint('[MokuroParser] HTML image extraction failed, '
            'trying dir listing for: $imageDirPath');
        imageFiles = await _listSortedImageFiles(imageDirPath);
        debugPrint('[MokuroParser] Dir listing found: ${imageFiles.length}');
      }

      if (imageFiles.isEmpty) {
        final reason = '  "$stem": no images found '
            '(HTML extraction and dir listing both failed)';
        debugPrint('[MokuroParser] SKIP $reason');
        skipReasons.add(reason);
        continue;
      }

      debugPrint('[MokuroParser] OK "$title" — ${imageFiles.length} pages');

      manifests.add(MokuroBookManifest(
        title: title,
        htmlPath: htmlFile.path,
        imageDirPath: imageDirPath,
        ocrDirPath: ocrDirPath,
        imageFileNames: imageFiles,
      ));
    }

    if (manifests.isEmpty) {
      throw Exception(
        'Found ${htmlFiles.length} HTML file(s) but all were skipped:\n'
        '${skipReasons.join("\n")}\n\n'
        'Expected folder structure:\n'
        '  <dir>/BookName.html\n'
        '  <dir>/BookName/        (page images)\n'
        '  <dir>/_ocr/BookName/   (OCR JSON files)',
      );
    }

    return manifests;
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
  /// Returns a [MokuroBookManifest] and the pre-parsed [MokuroPage] list.
  static Future<(MokuroBookManifest, List<MokuroPage>)> parseMokuroFile(
    String mokuroFilePath,
  ) async {
    final file = File(mokuroFilePath);
    if (!await file.exists()) {
      throw Exception('Mokuro file not found: $mokuroFilePath');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final title = (json['title'] as String?) ??
        (json['volume'] as String?) ??
        p.basenameWithoutExtension(mokuroFilePath);
    final volume = (json['volume'] as String?) ??
        p.basenameWithoutExtension(mokuroFilePath);

    final parentDir = p.dirname(mokuroFilePath);

    // Resolve the image directory. Try:
    // 1. Sibling directory matching the volume name
    // 2. Sibling directory matching the mokuro file stem
    // 3. The parent directory itself (images alongside .mokuro file)
    String? imageDirPath;
    final volumeDir = Directory(p.join(parentDir, volume));
    final stemDir = Directory(
      p.join(parentDir, p.basenameWithoutExtension(mokuroFilePath)),
    );

    if (await volumeDir.exists()) {
      imageDirPath = volumeDir.path;
    } else if (volume != p.basenameWithoutExtension(mokuroFilePath) &&
        await stemDir.exists()) {
      imageDirPath = stemDir.path;
    } else {
      // Images might be in the same directory as the .mokuro file
      imageDirPath = parentDir;
    }

    debugPrint('[MokuroParser] .mokuro file: $mokuroFilePath');
    debugPrint('[MokuroParser] Image dir resolved to: $imageDirPath');

    final pagesJson = json['pages'] as List;
    final pages = <MokuroPage>[];
    final imageFileNames = <String>[];

    for (int i = 0; i < pagesJson.length; i++) {
      final pageJson = pagesJson[i] as Map<String, dynamic>;
      final imgPath = pageJson['img_path'] as String;
      // img_path may contain a relative path like "VolumeName/0001.jpg"
      final imageFileName = p.basename(imgPath);
      imageFileNames.add(imageFileName);

      final blocks = (pageJson['blocks'] as List)
          .map((b) => MokuroTextBlock.fromOcrJson(b as Map<String, dynamic>))
          .toList();

      pages.add(MokuroPage(
        pageIndex: i,
        imageFileName: imageFileName,
        imgWidth: pageJson['img_width'] as int,
        imgHeight: pageJson['img_height'] as int,
        blocks: blocks,
      ));
    }

    debugPrint('[MokuroParser] Parsed ${pages.length} pages from .mokuro file');

    final manifest = MokuroBookManifest(
      title: title,
      htmlPath: mokuroFilePath, // reuse field for the source file path
      imageDirPath: imageDirPath,
      ocrDirPath: '', // not applicable for .mokuro format
      imageFileNames: imageFileNames,
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
    debugPrint('[MokuroParser]   exists=${await htmlFile.exists()}, '
        'path=${htmlFile.path}');
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
        final fullPath = match.group(1)!;
        // URL-decode the path and take just the filename
        final decoded = Uri.decodeFull(fullPath);
        final fileName = p.basename(decoded);
        imageFiles.add(fileName);
      }

      // Deduplicate while preserving order
      final seen = <String>{};
      final unique = <String>[];
      for (final f in imageFiles) {
        if (seen.add(f)) unique.add(f);
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

  /// Discover books purely from directory structure when HTML files
  /// are not accessible (e.g. Android scoped storage hiding files).
  ///
  /// For each non-_ocr subdirectory that has a matching _ocr subfolder,
  /// discovers image filenames by probing for sequential OCR JSON files
  /// (since [Directory.list] may not see files on Android).
  static Future<List<MokuroBookManifest>> _discoverFromDirectories(
    String dirPath,
    Map<String, String> dirsByName,
    Map<String, String> ocrSubDirs,
  ) async {
    final manifests = <MokuroBookManifest>[];
    final skipReasons = <String>[];

    for (final entry in dirsByName.entries) {
      if (entry.key == '_ocr') continue;
      final stem = entry.key;
      final imageDirPath = entry.value;

      debugPrint('[MokuroParser] Dir-based discovery: $stem');

      // Must have matching OCR subfolder
      final ocrDirPath = ocrSubDirs[stem];
      if (ocrDirPath == null) {
        skipReasons.add('  "$stem": no matching _ocr subfolder');
        continue;
      }

      // Try directory listing first (works on desktop/iOS)
      var imageFiles = await _listSortedImageFiles(imageDirPath);

      // Fallback: probe for sequential OCR JSON files to discover
      // image filenames (needed on Android where dir.list() fails)
      if (imageFiles.isEmpty) {
        debugPrint('[MokuroParser] Dir listing failed for $stem, '
            'probing OCR files');
        imageFiles = await _probeImageFilesFromOcr(ocrDirPath);
      }

      if (imageFiles.isEmpty) {
        skipReasons.add('  "$stem": no images found '
            '(dir listing and OCR probing both failed)');
        continue;
      }

      // Clean up the directory name for display as title
      final title = _cleanDirectoryTitle(stem);

      debugPrint('[MokuroParser] OK "$title" — ${imageFiles.length} pages');

      manifests.add(MokuroBookManifest(
        title: title,
        htmlPath: '', // not available
        imageDirPath: imageDirPath,
        ocrDirPath: ocrDirPath,
        imageFileNames: imageFiles,
      ));
    }

    if (manifests.isEmpty) {
      throw Exception(
        'Found image folders but could not match them to OCR data:\n'
        '${skipReasons.join("\n")}\n\n'
        'Expected: each image folder should have a matching '
        'subfolder in _ocr/',
      );
    }

    return manifests;
  }

  /// Probe for image filenames by checking which OCR JSON files exist.
  ///
  /// Mokuro generates sequential filenames. This method probes common
  /// naming patterns (e.g. `0.json`, `00001.json`, `001.json`) and
  /// derives image filenames by assuming `.jpg` extension (mokuro default).
  ///
  /// Used as a last resort when both HTML parsing and [Directory.list]
  /// fail (Pass 3 on Android).
  static Future<List<String>> _probeImageFilesFromOcr(
    String ocrDirPath,
  ) async {
    // Try common mokuro naming patterns
    final patterns = <String Function(int)>[
      // No padding, starting from 0: 0.json, 1.json, ...
      (i) => '$i.json',
      // 5-digit padding, starting from 1: 00001.json, 00002.json, ...
      (i) => '${(i + 1).toString().padLeft(5, '0')}.json',
      // 3-digit padding, starting from 1: 001.json, 002.json, ...
      (i) => '${(i + 1).toString().padLeft(3, '0')}.json',
    ];

    for (final pattern in patterns) {
      // Check if the first file exists for this pattern
      final firstPath = p.join(ocrDirPath, pattern(0));
      debugPrint('[MokuroParser] OCR probe: trying $firstPath');
      if (!await File(firstPath).exists()) continue;

      debugPrint('[MokuroParser] OCR probe: pattern ${pattern(0)} matched');

      // Found a pattern — enumerate all files
      final imageFiles = <String>[];
      for (var i = 0; i < 9999; i++) {
        final jsonName = pattern(i);
        final jsonPath = p.join(ocrDirPath, jsonName);
        if (!await File(jsonPath).exists()) break;

        // Derive image filename: same stem with .jpg (mokuro convention)
        final stem = p.basenameWithoutExtension(jsonName);
        imageFiles.add('$stem.jpg');
      }

      debugPrint('[MokuroParser] OCR probe found ${imageFiles.length} pages');
      return imageFiles;
    }

    return [];
  }

  /// Clean a directory name for use as a book title.
  /// Strips resolution suffixes like "-2k" and whitespace.
  static String _cleanDirectoryTitle(String dirName) {
    var title = dirName;
    // Strip trailing resolution suffixes: -2k, -4k, etc.
    title = title.replaceFirst(RegExp(r'-\d+k$', caseSensitive: false), '');
    return title.trim();
  }

  /// Parse a single OCR JSON file into a [MokuroPage].
  static Future<MokuroPage> parseOcrJson(
    String jsonPath,
    int pageIndex,
    String imageFileName,
  ) async {
    final content = await File(jsonPath).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final blocks = (json['blocks'] as List)
        .map((b) => MokuroTextBlock.fromOcrJson(b as Map<String, dynamic>))
        .toList();

    return MokuroPage(
      pageIndex: pageIndex,
      imageFileName: imageFileName,
      imgWidth: json['img_width'] as int,
      imgHeight: json['img_height'] as int,
      blocks: blocks,
    );
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
      final imageStem = p.basenameWithoutExtension(imageFileName);
      final ocrJsonPath = p.join(ocrDirPath, '$imageStem.json');

      if (await File(ocrJsonPath).exists()) {
        pages.add(await parseOcrJson(ocrJsonPath, i, imageFileName));
      } else {
        // No OCR data for this page — include as blank overlay.
        pages.add(MokuroPage(
          pageIndex: i,
          imageFileName: imageFileName,
          imgWidth: 0,
          imgHeight: 0,
          blocks: const [],
        ));
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
    final imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};

    final files = <String>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (imageExtensions.contains(ext)) {
            files.add(p.basename(entity.path));
          }
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
    final len =
        aSegments.length < bSegments.length ? aSegments.length : bSegments.length;

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
