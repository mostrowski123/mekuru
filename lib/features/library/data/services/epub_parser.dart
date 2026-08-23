import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Metadata extracted from an EPUB file.
class EpubMetadata {
  final String title;
  final String? author;
  final String? coverImageRelativePath;
  final String? language;
  final String? pageProgressionDirection;

  /// The `primary-writing-mode` from OPF metadata (e.g. `vertical-rl`,
  /// `horizontal-tb`). Used to determine whether content is vertical text
  /// independently of page-progression-direction.
  final String? primaryWritingMode;

  /// Whether any stylesheet or content document declares a vertical
  /// `writing-mode`. Fallback vertical-text signal for EPUBs whose OPF
  /// lacks `primary-writing-mode` (true vertical books always declare
  /// `writing-mode: vertical-rl` in CSS).
  final bool hasVerticalCss;

  const EpubMetadata({
    required this.title,
    this.author,
    this.coverImageRelativePath,
    this.language,
    this.pageProgressionDirection,
    this.primaryWritingMode,
    required this.hasVerticalCss,
  });
}

/// Maximum EPUB import size. The bound is the reader, not import (which
/// works entry-at-a-time): the WebView JS heap must hold the whole file
/// (`_epubBuf` in reader_bridge.js) plus epub.js's parsed book.
const _maxEpubBytes = 400 * 1024 * 1024;

/// Files above this trigger the low-memory import warning: the old import
/// cap, below which months of installs produced no reader OOM reports.
const largeEpubWarnBytes = 200 * 1024 * 1024;

/// Total-RAM floor for that warning — the reader holds the whole file in the
/// WebView JS heap, so low-RAM devices are the likely first casualty.
/// ponytail: heuristic cutoff, revisit if Sentry shows renderer OOMs.
const lowRamDeviceThresholdMb = 4096;

/// Matches a vertical `writing-mode` CSS declaration, including the
/// `-epub-`/`-webkit-` vendor prefixes and the legacy `tb-rl`/`tb-lr` values.
final _verticalWritingModeCss = RegExp(
  r'writing-mode\s*:\s*(?:vertical|tb-rl|tb-lr)',
  caseSensitive: false,
);

const _stylesheetExtension = '.css';

/// Content documents can carry the declaration in inline styles or
/// `<style>` blocks.
const _contentDocExtensions = {'.xhtml', '.html', '.htm'};

bool _declaresVerticalWritingMode(List<int> bytes) =>
    _verticalWritingModeCss.hasMatch(utf8.decode(bytes, allowMalformed: true));

/// Parses EPUB files to extract metadata and cover images.
class EpubParser {
  /// Title used when the EPUB metadata has no usable title: the file's own
  /// name, which is far more recognizable in the library than a generic
  /// "Unknown Title".
  static String _fallbackTitleFor(String epubPath) =>
      p.basenameWithoutExtension(epubPath);

  /// Throws when [file] exceeds the import size cap.
  ///
  /// Public so import can reject the source file *before* copying it into
  /// app storage — a rejected import must not strand a full-size copy.
  static Future<void> ensureWithinSizeCap(File file) async {
    final fileSize = await file.length();
    if (fileSize > _maxEpubBytes) {
      // ceil() so a barely-over file never reads back as equal to the cap
      // (Sentry MEKURU-1D).
      throw FileSystemException(
        'EPUB file is too large (${(fileSize / 1024 / 1024).ceil()} MB). '
        'Maximum supported size is ${_maxEpubBytes ~/ 1024 ~/ 1024} MB.',
        file.path,
      );
    }
  }

  /// archive throws ArgumentError/RangeError on truncated streams and
  /// FormatException on bad signatures; surface either as a clean
  /// "corrupt EPUB" rather than a raw RangeError to the import flow.
  static Archive _decodeOrThrow(InputFileStream input, String epubPath) {
    try {
      return ZipDecoder().decodeStream(input);
    } catch (e) {
      throw FileSystemException(
        'EPUB file is corrupt or not a valid archive',
        epubPath,
      );
    }
  }

  /// Parse an EPUB file and extract its metadata + cover image.
  ///
  /// [epubPath] is the path to the .epub file.
  /// [extractDir] is where the EPUB contents will be unzipped.
  /// Returns [EpubMetadata] with title, author, and cover path.
  static Future<EpubMetadata> parseEpub(
    String epubPath,
    String extractDir,
  ) async {
    final file = File(epubPath);
    if (!await file.exists()) {
      throw FileSystemException('EPUB file not found', epubPath);
    }
    await ensureWithinSizeCap(file);

    // Stream-decode the EPUB ZIP to avoid loading the entire file into memory.
    var hasVerticalCss = false;
    final input = InputFileStream(epubPath);
    try {
      final archive = _decodeOrThrow(input, epubPath);

      hasVerticalCss = _sniffVerticalCss(archive);

      // Extract entry-by-entry, clearing each one — ArchiveFile.content
      // caches decompressed bytes forever, so without clear() the whole
      // decompressed EPUB accumulates in the Dart heap (Sentry MEKURU-1D).
      final createdDirs = <String>{};
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final outFile = File(p.join(extractDir, entry.name));
        if (createdDirs.add(outFile.parent.path)) {
          await outFile.parent.create(recursive: true);
        }
        await outFile.writeAsBytes(entry.content as List<int>);
        // clear(), never close(): every entry shares the InputFileStream's
        // single file handle — closing one empties all later entries.
        entry.clear();
      }
    } finally {
      input.close();
    }

    // 1. Parse META-INF/container.xml to find the OPF file path
    final opfPath = await _findOpfPath(extractDir);
    if (opfPath == null) {
      return EpubMetadata(
        title: _fallbackTitleFor(epubPath),
        hasVerticalCss: hasVerticalCss,
      );
    }

    // 2. Parse the OPF file for title, author, cover
    return _parseOpf(
      extractDir,
      opfPath,
      fallbackTitle: _fallbackTitleFor(epubPath),
      hasVerticalCss: hasVerticalCss,
    );
  }

  /// Parse only metadata from an EPUB without full extraction.
  /// Useful for previewing before committing to import.
  static Future<EpubMetadata> parseMetadataOnly(String epubPath) async {
    final file = File(epubPath);
    if (!await file.exists()) {
      throw FileSystemException('EPUB file not found', epubPath);
    }
    await ensureWithinSizeCap(file);

    // Stream-decode the archive: the OPF metadata needs only 2 small XML
    // files; the vertical-CSS sniff additionally inflates stylesheet and
    // content entries (CSS first, so vertical books stop early).
    final fallbackTitle = _fallbackTitleFor(epubPath);
    final input = InputFileStream(epubPath);
    try {
      final archive = _decodeOrThrow(input, epubPath);

      final hasVerticalCss = _sniffVerticalCss(archive);
      EpubMetadata fallback() =>
          EpubMetadata(title: fallbackTitle, hasVerticalCss: hasVerticalCss);

      // Find container.xml in the archive
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) {
        return fallback();
      }

      final containerXml = XmlDocument.parse(
        utf8.decode(containerFile.content as List<int>),
      );
      final opfPath = extractOpfPathFromXml(containerXml);
      if (opfPath == null) {
        return fallback();
      }

      // Find the OPF file in the archive
      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) {
        return fallback();
      }

      final opfXml = XmlDocument.parse(
        utf8.decode(opfFile.content as List<int>),
      );
      final opfDir = p.dirname(opfPath);

      return _extractMetadataFromOpf(
        opfXml,
        opfDir,
        fallbackTitle: fallbackTitle,
        hasVerticalCss: hasVerticalCss,
      );
    } finally {
      input.close();
    }
  }

  /// Whether any stylesheet or content document in [archive] declares a
  /// vertical writing-mode.
  ///
  /// Stylesheets nearly always carry the declaration and are tiny next to
  /// content documents, so they are scanned first — vertical books
  /// short-circuit before every chapter is inflated.
  static bool _sniffVerticalCss(Archive archive) =>
      _anyEntryDeclaresVertical(
        archive,
        (ext) => ext == _stylesheetExtension,
      ) ||
      _anyEntryDeclaresVertical(archive, _contentDocExtensions.contains);

  static bool _anyEntryDeclaresVertical(
    Archive archive,
    bool Function(String extension) wanted,
  ) {
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (!wanted(p.extension(entry.name).toLowerCase())) continue;
      // rawContent.getStream() inflates without caching — `.content` would
      // pin every sniffed chapter in memory at once for horizontal books.
      final raw = entry.rawContent;
      if (raw != null &&
          _declaresVerticalWritingMode(raw.getStream().toUint8List())) {
        return true;
      }
    }
    return false;
  }

  /// Find the OPF file path from META-INF/container.xml.
  static Future<String?> _findOpfPath(String extractDir) async {
    final containerPath = p.join(extractDir, 'META-INF', 'container.xml');
    final containerFile = File(containerPath);
    if (!await containerFile.exists()) return null;

    final containerXml = XmlDocument.parse(await containerFile.readAsString());
    return extractOpfPathFromXml(containerXml);
  }

  /// Extract the OPF path from a parsed container.xml document.
  static String? extractOpfPathFromXml(XmlDocument containerXml) {
    // <rootfile full-path="OEBPS/content.opf" .../>
    final rootfiles = containerXml.findAllElements('rootfile');
    if (rootfiles.isEmpty) return null;

    return rootfiles.first.getAttribute('full-path');
  }

  /// Parse the OPF file for metadata and cover image path.
  static Future<EpubMetadata> _parseOpf(
    String extractDir,
    String opfPath, {
    required String fallbackTitle,
    required bool hasVerticalCss,
  }) async {
    final opfFile = File(p.join(extractDir, opfPath));
    if (!await opfFile.exists()) {
      return EpubMetadata(title: fallbackTitle, hasVerticalCss: hasVerticalCss);
    }

    final opfXml = XmlDocument.parse(await opfFile.readAsString());
    final opfDir = p.dirname(opfPath);

    return _extractMetadataFromOpf(
      opfXml,
      opfDir,
      fallbackTitle: fallbackTitle,
      hasVerticalCss: hasVerticalCss,
    );
  }

  /// Extract metadata from a parsed OPF XML document.
  static EpubMetadata _extractMetadataFromOpf(
    XmlDocument opfXml,
    String opfDir, {
    required String fallbackTitle,
    required bool hasVerticalCss,
  }) {
    // Extract title from <dc:title>, falling back to <title> without the
    // namespace prefix, then to the EPUB's own filename.
    String? title;
    for (final tag in const ['dc:title', 'title']) {
      final elements = opfXml.findAllElements(tag);
      if (elements.isEmpty) continue;
      final t = elements.first.innerText.trim();
      if (t.isNotEmpty) {
        title = t;
        break;
      }
    }

    // Extract author from <dc:creator>
    String? author;
    final creatorElements = opfXml.findAllElements('dc:creator');
    if (creatorElements.isNotEmpty) {
      author = creatorElements.first.innerText.trim();
    }
    if (author == null) {
      final creatorElements2 = opfXml.findAllElements('creator');
      if (creatorElements2.isNotEmpty) {
        author = creatorElements2.first.innerText.trim();
      }
    }

    // Extract cover image path
    String? coverRelativePath;

    // Strategy 1: Look for <meta name="cover" content="cover-image-id"/>
    final metaElements = opfXml.findAllElements('meta');
    String? coverId;
    for (final meta in metaElements) {
      if (meta.getAttribute('name') == 'cover') {
        coverId = meta.getAttribute('content');
        break;
      }
    }

    // Strategy 2: Look for <item> with id matching coverId or properties="cover-image"
    final manifestItems = opfXml.findAllElements('item');
    for (final item in manifestItems) {
      final itemId = item.getAttribute('id');
      final properties = item.getAttribute('properties') ?? '';
      final href = item.getAttribute('href');

      if (href == null) continue;

      // Match by cover id from meta
      if (coverId != null && itemId == coverId) {
        coverRelativePath = p.join(opfDir, href);
        break;
      }

      // Match by properties="cover-image" (EPUB 3)
      if (properties.contains('cover-image')) {
        coverRelativePath = p.join(opfDir, href);
        break;
      }
    }

    // Strategy 3: Look for item with id containing "cover" and image media type
    if (coverRelativePath == null) {
      for (final item in manifestItems) {
        final itemId = item.getAttribute('id')?.toLowerCase() ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        final href = item.getAttribute('href');

        if (href != null &&
            itemId.contains('cover') &&
            mediaType.startsWith('image/')) {
          coverRelativePath = p.join(opfDir, href);
          break;
        }
      }
    }

    // Extract language from <dc:language>
    String? language;
    final langElements = opfXml.findAllElements('dc:language');
    if (langElements.isNotEmpty) {
      language = langElements.first.innerText.trim().toLowerCase();
    }
    // Fallback: try without namespace prefix
    if (language == null) {
      final langElements2 = opfXml.findAllElements('language');
      if (langElements2.isNotEmpty) {
        language = langElements2.first.innerText.trim().toLowerCase();
      }
    }
    // Normalize to primary subtag only (e.g., "en-US" → "en")
    if (language != null && language.contains('-')) {
      language = language.split('-').first;
    }

    // Extract page-progression-direction from <spine>
    String? pageProgressionDirection;
    final spineElements = opfXml.findAllElements('spine');
    if (spineElements.isNotEmpty) {
      pageProgressionDirection = spineElements.first.getAttribute(
        'page-progression-direction',
      );
    }

    // Extract primary-writing-mode from <meta name="primary-writing-mode">
    String? primaryWritingMode;
    for (final meta in metaElements) {
      if (meta.getAttribute('name') == 'primary-writing-mode') {
        primaryWritingMode = meta.getAttribute('content')?.toLowerCase();
        break;
      }
    }

    return EpubMetadata(
      title: title ?? fallbackTitle,
      author: author,
      coverImageRelativePath: coverRelativePath,
      language: language,
      pageProgressionDirection: pageProgressionDirection,
      primaryWritingMode: primaryWritingMode,
      hasVerticalCss: hasVerticalCss,
    );
  }
}
