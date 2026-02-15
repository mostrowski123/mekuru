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

  const EpubMetadata({
    required this.title,
    this.author,
    this.coverImageRelativePath,
  });
}

/// Parses EPUB files to extract metadata and cover images.
class EpubParser {
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

    // Unzip the EPUB
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Extract all files
    for (final entry in archive.files) {
      if (entry.isFile) {
        final outFile = File(p.join(extractDir, entry.name));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      }
    }

    // 1. Parse META-INF/container.xml to find the OPF file path
    final opfPath = await _findOpfPath(extractDir);
    if (opfPath == null) {
      return const EpubMetadata(title: 'Unknown Title');
    }

    // 2. Parse the OPF file for title, author, cover
    return _parseOpf(extractDir, opfPath);
  }

  /// Parse only metadata from an EPUB without full extraction.
  /// Useful for previewing before committing to import.
  static Future<EpubMetadata> parseMetadataOnly(String epubPath) async {
    final file = File(epubPath);
    if (!await file.exists()) {
      throw FileSystemException('EPUB file not found', epubPath);
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find container.xml in the archive
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      return const EpubMetadata(title: 'Unknown Title');
    }

    final containerXml = XmlDocument.parse(
      utf8.decode(containerFile.content as List<int>),
    );
    final opfPath = _extractOpfPathFromXml(containerXml);
    if (opfPath == null) {
      return const EpubMetadata(title: 'Unknown Title');
    }

    // Find the OPF file in the archive
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      return const EpubMetadata(title: 'Unknown Title');
    }

    final opfXml = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));
    final opfDir = p.dirname(opfPath);

    return _extractMetadataFromOpf(opfXml, opfDir);
  }

  /// Find the OPF file path from META-INF/container.xml.
  static Future<String?> _findOpfPath(String extractDir) async {
    final containerPath = p.join(extractDir, 'META-INF', 'container.xml');
    final containerFile = File(containerPath);
    if (!await containerFile.exists()) return null;

    final containerXml = XmlDocument.parse(await containerFile.readAsString());
    return _extractOpfPathFromXml(containerXml);
  }

  /// Extract the OPF path from a parsed container.xml document.
  static String? _extractOpfPathFromXml(XmlDocument containerXml) {
    // <rootfile full-path="OEBPS/content.opf" .../>
    final rootfiles = containerXml.findAllElements('rootfile');
    if (rootfiles.isEmpty) return null;

    return rootfiles.first.getAttribute('full-path');
  }

  /// Parse the OPF file for metadata and cover image path.
  static Future<EpubMetadata> _parseOpf(
    String extractDir,
    String opfPath,
  ) async {
    final opfFile = File(p.join(extractDir, opfPath));
    if (!await opfFile.exists()) {
      return const EpubMetadata(title: 'Unknown Title');
    }

    final opfXml = XmlDocument.parse(await opfFile.readAsString());
    final opfDir = p.dirname(opfPath);

    return _extractMetadataFromOpf(opfXml, opfDir);
  }

  /// Extract metadata from a parsed OPF XML document.
  static EpubMetadata _extractMetadataFromOpf(
    XmlDocument opfXml,
    String opfDir,
  ) {
    // Extract title from <dc:title>
    String title = 'Unknown Title';
    final titleElements = opfXml.findAllElements('dc:title');
    if (titleElements.isNotEmpty) {
      title = titleElements.first.innerText.trim();
    }
    // Fallback: try without namespace prefix
    if (title == 'Unknown Title') {
      final titleElements2 = opfXml.findAllElements('title');
      if (titleElements2.isNotEmpty) {
        title = titleElements2.first.innerText.trim();
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

    return EpubMetadata(
      title: title,
      author: author,
      coverImageRelativePath: coverRelativePath,
    );
  }
}
