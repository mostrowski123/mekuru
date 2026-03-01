import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
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

  static bool _isImageFile(String fileName) =>
      _imageExtensions.contains(p.extension(fileName).toLowerCase());

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

    debugPrint(
      '[MokuroParser] Listed files: ${listedFiles.length}, '
      'dirs: ${listedDirs.length}',
    );
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
    var htmlFiles =
        listedFiles
            .where(
              (f) =>
                  f.path.endsWith('.html') && !f.path.endsWith('.mobile.html'),
            )
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
      debugPrint(
        '[MokuroParser] HTML files not accessible — '
        'discovering from directory structure only',
      );
      return _discoverFromDirectories(dirPath, dirsByName, ocrSubDirs);
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
        debugPrint(
          '[MokuroParser] HTML image extraction failed, '
          'trying dir listing for: $imageDirPath',
        );
        imageFiles = await _listSortedImageFiles(imageDirPath);
        debugPrint('[MokuroParser] Dir listing found: ${imageFiles.length}');
      }

      if (imageFiles.isEmpty) {
        final reason =
            '  "$stem": no images found '
            '(HTML extraction and dir listing both failed)';
        debugPrint('[MokuroParser] SKIP $reason');
        skipReasons.add(reason);
        continue;
      }

      debugPrint('[MokuroParser] OK "$title" — ${imageFiles.length} pages');

      manifests.add(
        MokuroBookManifest(
          title: title,
          htmlPath: htmlFile.path,
          imageDirPath: imageDirPath,
          ocrDirPath: ocrDirPath,
          imageFileNames: imageFiles,
        ),
      );
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

    // Log parent directory contents for diagnosis
    try {
      final entities = await Directory(parentDir).list().toList();
      debugPrint('[MokuroParser] Parent dir contents (${entities.length}):');
      for (final entity in entities) {
        final type = entity is Directory ? 'DIR' : 'FILE';
        debugPrint('[MokuroParser]   [$type] ${p.basename(entity.path)}');
      }
    } catch (e) {
      debugPrint('[MokuroParser] Cannot list parent dir: $e');
    }

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
    if (originalDirPath == null &&
        safTreeUri == null &&
        !await Directory(imageDirPath).exists()) {
      throw Exception(
        'Image folder not found: $imageDirPath\n'
        'Expected a folder named "$stem" next to the HTML file.',
      );
    }

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
        imageFiles = names.where(_isImageFile).toList()..sort(_naturalCompare);
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

    final title =
        (json['title'] as String?) ??
        (json['volume'] as String?) ??
        p.basenameWithoutExtension(mokuroFilePath);
    final volume =
        (json['volume'] as String?) ??
        p.basenameWithoutExtension(mokuroFilePath);

    final parentDir = originalDirPath ?? p.dirname(mokuroFilePath);
    final fileStem = p.basenameWithoutExtension(mokuroFilePath);
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

    // Log parent directory contents for diagnosis
    try {
      final entities = await Directory(parentDir).list().toList();
      debugPrint('[MokuroParser] Parent dir contents (${entities.length}):');
      for (final entity in entities) {
        final type = entity is Directory ? 'DIR' : 'FILE';
        debugPrint('[MokuroParser]   [$type] ${p.basename(entity.path)}');
      }
    } catch (e) {
      debugPrint('[MokuroParser] Cannot list parent dir: $e');
    }

    // Resolve the image directory. Try:
    // 1. Sibling directory matching the volume name
    // 2. Sibling directory matching the mokuro file stem
    // 3. The parent directory itself (images alongside .mokuro file)
    //
    // When originalDirPath is provided (Android file picker), skip
    // Directory.exists() checks — on Android 13+ without
    // MANAGE_EXTERNAL_STORAGE, directory metadata isn't accessible even
    // though the image files inside ARE readable via READ_MEDIA_IMAGES.
    // In that case, trust the volume/stem name and construct the path.
    late String imageDirPath;
    String? safImageDirRel;
    final volumeDirPath = p.join(parentDir, volume);
    final stemDirPath = p.join(parentDir, fileStem);

    if (safTreeUri != null) {
      // SAF-backed import — start with the volume-named folder and refine
      // below after we know which image filenames actually exist.
      imageDirPath = volumeDirPath;
      safImageDirRel = _joinSafRelative([safParentDirRel ?? '', volume]);
      debugPrint('[MokuroParser] Image dir (trusted): $imageDirPath');
    } else if (originalDirPath != null) {
      // Android legacy file picker path — skip exists() checks, use volume dir
      imageDirPath = volumeDirPath;
      debugPrint('[MokuroParser] Image dir (trusted): $imageDirPath');
    } else {
      final volumeDir = Directory(volumeDirPath);
      final stemDir = Directory(stemDirPath);

      debugPrint('[MokuroParser] Checking volume dir: ${volumeDir.path}');
      debugPrint('[MokuroParser]   exists: ${await volumeDir.exists()}');

      if (await volumeDir.exists()) {
        imageDirPath = volumeDir.path;
      } else if (volume != p.basenameWithoutExtension(mokuroFilePath) &&
          await stemDir.exists()) {
        debugPrint('[MokuroParser] Checking stem dir: ${stemDir.path}');
        debugPrint('[MokuroParser]   exists: ${await stemDir.exists()}');
        imageDirPath = stemDir.path;
      } else {
        debugPrint('[MokuroParser] Falling back to parent dir for images');
        imageDirPath = parentDir;
      }
    }

    debugPrint('[MokuroParser] Image dir resolved to: $imageDirPath');

    // Check we can actually list files in the image directory (diagnostic)
    try {
      final imgEntities = await Directory(imageDirPath).list().toList();
      debugPrint('[MokuroParser] Image dir contents (${imgEntities.length}):');
      for (final entity in imgEntities.take(5)) {
        debugPrint('[MokuroParser]   ${p.basename(entity.path)}');
      }
      if (imgEntities.length > 5) {
        debugPrint('[MokuroParser]   ... and ${imgEntities.length - 5} more');
      }
    } catch (e) {
      debugPrint('[MokuroParser] Cannot list image dir: $e');
    }

    final pagesJson = json['pages'] as List;
    final pages = <MokuroPage>[];
    final imageFileNames = <String>[];

    for (int i = 0; i < pagesJson.length; i++) {
      final pageJson = pagesJson[i] as Map<String, dynamic>;
      final imgPath = pageJson['img_path'] as String;
      // img_path may contain a relative path like "VolumeName/0001.jpg"
      final imageFileName = p.basename(imgPath);

      // Skip non-image entries (e.g. .nomedia, .json metadata)
      if (!_isImageFile(imageFileName)) continue;

      imageFileNames.add(imageFileName);

      final blocks = (pageJson['blocks'] as List)
          .map((b) => MokuroTextBlock.fromOcrJson(b as Map<String, dynamic>))
          .toList();

      pages.add(
        MokuroPage(
          pageIndex: pages.length,
          imageFileName: imageFileName,
          imgWidth: pageJson['img_width'] as int,
          imgHeight: pageJson['img_height'] as int,
          blocks: blocks,
        ),
      );
    }

    debugPrint('[MokuroParser] Parsed ${pages.length} pages from .mokuro file');

    if (safTreeUri != null) {
      final firstImage = imageFileNames.isNotEmpty
          ? imageFileNames.first
          : null;
      final volumeRel = _joinSafRelative([safParentDirRel ?? '', volume]);
      final stemRel = _joinSafRelative([safParentDirRel ?? '', fileStem]);
      final parentRel = safParentDirRel ?? '';
      final candidates = <(String rel, String abs)>[
        (volumeRel, volumeDirPath),
        (stemRel, stemDirPath),
        (parentRel, parentDir),
      ];

      if (firstImage != null) {
        for (final candidate in candidates) {
          final exists = await AndroidSafService.existsInTreePath(
            safTreeUri,
            _joinSafRelative([candidate.$1, firstImage]),
          );
          if (exists) {
            safImageDirRel = candidate.$1;
            imageDirPath = candidate.$2;
            break;
          }
        }
      } else {
        safImageDirRel = volumeRel;
        imageDirPath = volumeDirPath;
      }
    }

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
        final fullPath = match.group(1)!;
        // URL-decode the path and take just the filename
        final decoded = Uri.decodeFull(fullPath);
        final fileName = p.basename(decoded);
        imageFiles.add(fileName);
      }

      // Deduplicate while preserving order, skip non-image files
      final seen = <String>{};
      final unique = <String>[];
      for (final f in imageFiles) {
        if (_isImageFile(f) && seen.add(f)) unique.add(f);
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
        debugPrint(
          '[MokuroParser] Dir listing failed for $stem, '
          'probing OCR files',
        );
        imageFiles = await _probeImageFilesFromOcr(ocrDirPath);
      }

      if (imageFiles.isEmpty) {
        skipReasons.add(
          '  "$stem": no images found '
          '(dir listing and OCR probing both failed)',
        );
        continue;
      }

      // Clean up the directory name for display as title
      final title = _cleanDirectoryTitle(stem);

      debugPrint('[MokuroParser] OK "$title" — ${imageFiles.length} pages');

      manifests.add(
        MokuroBookManifest(
          title: title,
          htmlPath: '', // not available
          imageDirPath: imageDirPath,
          ocrDirPath: ocrDirPath,
          imageFileNames: imageFiles,
        ),
      );
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
  static Future<List<String>> _probeImageFilesFromOcr(String ocrDirPath) async {
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
    return _parseOcrJsonContent(content, pageIndex, imageFileName);
  }

  static MokuroPage _parseOcrJsonContent(
    String content,
    int pageIndex,
    String imageFileName,
  ) {
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
      final imageStem = p.basenameWithoutExtension(imageFileName);
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
      final imageStem = p.basenameWithoutExtension(imageFileName);
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
        if (entity is File && _isImageFile(entity.path)) {
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
      return computeImageContentBoundsFromBytes(
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
    final codec = await ui.instantiateImageCodec(bytes);
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

    bool isWhitePixel(int offset) =>
        pixels[offset] >= thresh &&
        pixels[offset + 1] >= thresh &&
        pixels[offset + 2] >= thresh;

    // Track the closest non-white pixel on each side independently.
    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;

    for (int y = 0; y < height; y++) {
      final rowBase = y * width * 4;
      for (int x = 0; x < width; x++) {
        final offset = rowBase + x * 4;
        if (isWhitePixel(offset)) continue;

        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    // Entirely white page
    if (maxX < 0 || maxY < 0) return null;

    return ui.Rect.fromLTRB(
      (minX.toDouble() - padding).clamp(0.0, width.toDouble()),
      (minY.toDouble() - padding).clamp(0.0, height.toDouble()),
      // +1 because maxX/maxY are inclusive pixel indices
      (maxX.toDouble() + 1 + padding).clamp(0.0, width.toDouble()),
      (maxY.toDouble() + 1 + padding).clamp(0.0, height.toDouble()),
    );
  }

  /// Computes [contentBounds] for all pages by scanning their images.
  static Future<List<MokuroPage>> computeAllContentBounds(
    List<MokuroPage> pages,
    String imageDirPath,
  ) async {
    final result = <MokuroPage>[];
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final imagePath = p.join(imageDirPath, page.imageFileName);
      final bounds = await computeImageContentBounds(imagePath);
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
    String imageDirRelativePath,
  ) async {
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
          bounds = await computeImageContentBoundsFromBytes(bytes);
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
