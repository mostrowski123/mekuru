import 'dart:io';

import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Thrown when an EPUB does not look like a fixed-layout (image-per-page)
/// manga and therefore cannot be converted to a manga book.
class EpubNotMangaException implements Exception {
  final String message;
  const EpubNotMangaException(this.message);

  @override
  String toString() => 'EpubNotMangaException: $message';
}

/// Scans an extracted EPUB (`content/` directory) and, when (nearly) every
/// spine document resolves to exactly one image, returns those images'
/// absolute paths in spine order, de-duplicated. Returns null when the book
/// does not look like a manga.
///
/// Read-only: safe to call without any cleanup obligation.
Future<List<String>?> _planConversion(String contentDir) async {
  final String? opfPath;
  final XmlDocument opfXml;
  try {
    opfPath = await EpubParser.findOpfPath(contentDir);
    if (opfPath == null) return null;
    opfXml = XmlDocument.parse(
      await File(p.join(contentDir, opfPath)).readAsString(),
    );
  } on Exception {
    return null;
  }

  final manifestHrefById = <String, String>{
    for (final item in opfXml.findAllElements('item'))
      if (item.getAttribute('id') != null && item.getAttribute('href') != null)
        item.getAttribute('id')!: item.getAttribute('href')!,
  };

  final spines = opfXml.findAllElements('spine');
  if (spines.isEmpty) return null;
  final itemrefs = spines.first.findElements('itemref').toList();
  if (itemrefs.isEmpty) return null;

  final opfDir = p.posix.dirname(opfPath);
  final seen = <String>{};
  final sourceImagePaths = <String>[];
  var imageDocCount = 0;

  for (final itemref in itemrefs) {
    final href = manifestHrefById[itemref.getAttribute('idref')];
    if (href == null) continue;
    final docPath = _resolveRelative(opfDir, href);
    if (docPath == null) continue;

    final image = await _singleImageOf(contentDir, docPath);
    if (image == null) continue;
    // A duplicate (the cover XHTML and a page pointing at the same file)
    // still counts as an image doc for eligibility, but yields one page.
    imageDocCount++;
    if (seen.add(image)) sourceImagePaths.add(p.join(contentDir, image));
  }

  final eligible =
      sourceImagePaths.length >= 3 && imageDocCount / itemrefs.length >= 0.9;
  return eligible ? sourceImagePaths : null;
}

/// Resolves [ref] against [baseDir] (both root-relative POSIX paths inside
/// the EPUB), returning null for refs that are unusable or escape the root.
String? _resolveRelative(String baseDir, String ref) {
  final bare = ref.split('#').first.split('?').first;
  if (bare.isEmpty || bare.startsWith('data:')) return null;
  if (Uri.tryParse(bare)?.hasScheme ?? false) return null;
  final String decoded;
  try {
    decoded = Uri.decodeFull(bare);
  } on ArgumentError {
    return null;
  }
  final resolved = p.posix.normalize(p.posix.join(baseDir, decoded));
  if (resolved.startsWith('..')) return null;
  return resolved;
}

/// Returns the root-relative path of the single page image referenced by the
/// spine document at [docPath], or null when the doc is not an
/// exactly-one-image page.
Future<String?> _singleImageOf(String contentDir, String docPath) async {
  final XmlDocument? doc;
  try {
    doc = parseXhtml(await File(p.join(contentDir, docPath)).readAsString());
  } on Exception {
    return null;
  }
  if (doc == null) return null;

  final docDir = p.posix.dirname(docPath);
  final refs = <String>[
    for (final el in doc.findAllElements('img'))
      if (el.getAttribute('src') != null) el.getAttribute('src')!,
    // SVG-wrapped pages: match the href attribute by local name so both
    // xlink:href and plain href are caught.
    for (final el in doc.findAllElements('image'))
      for (final attr in el.attributes)
        if (attr.name.local == 'href') attr.value,
  ];

  final resolved = <String>{};
  for (final ref in refs) {
    final rel = _resolveRelative(docDir, ref);
    if (rel == null) continue;
    if (!CbzParser.imageExtensions.contains(p.extension(rel).toLowerCase())) {
      continue;
    }
    if (!await File(p.join(contentDir, rel)).exists()) continue;
    resolved.add(rel);
  }

  // Exactly one distinct image makes a manga page; more means this is not a
  // page-per-image doc, and silently taking the first would drop content.
  return resolved.length == 1 ? resolved.single : null;
}

/// compute() entry point: (contentDir, bookDir) → pages with empty blocks.
///
/// Moves every planned page image out of [contentDir] into
/// `[bookDir]/images/` under zero-padded names, then reads each page's
/// dimensions from its file header. Rolls the moves back and rethrows on
/// failure. Throws [EpubNotMangaException] when the EPUB is not eligible.
Future<List<MokuroPage>> applyEpubMangaConversion((String, String) args) async {
  final (contentDir, bookDir) = args;
  final sourceImagePaths = await _planConversion(contentDir);
  if (sourceImagePaths == null) {
    throw const EpubNotMangaException(
      'EPUB spine is not composed of single-image pages',
    );
  }

  final imagesDir = Directory(p.join(bookDir, 'images'));
  await imagesDir.create(recursive: true);

  // ponytail: a process kill mid-loop strands half-moved images; the loop is
  // millisecond-scale (same-filesystem renames), so no resume journal.
  final moved = <(String, String)>[];
  try {
    for (var i = 0; i < sourceImagePaths.length; i++) {
      final source = sourceImagePaths[i];
      final target = p.join(
        imagesDir.path,
        CbzParser.pageFileName(i + 1, source),
      );
      await File(source).rename(target);
      moved.add((source, target));
    }
  } catch (_) {
    for (final (source, target) in moved) {
      try {
        await File(target).rename(source);
      } catch (_) {
        // Best-effort — leave what cannot be restored.
      }
    }
    try {
      await imagesDir.delete(recursive: true);
    } catch (_) {}
    rethrow;
  }

  // Kept out of the rename loop on purpose: an unreadable header must degrade
  // to 0x0, not roll back the whole conversion.
  final pages = <MokuroPage>[];
  for (var i = 0; i < moved.length; i++) {
    final target = moved[i].$2;
    final dims = await readImageDimensionsFromFile(target);
    pages.add(
      MokuroPage(
        pageIndex: i,
        imageFileName: p.basename(target),
        imgWidth: dims?.width ?? 0,
        imgHeight: dims?.height ?? 0,
        blocks: const [],
      ),
    );
  }
  return pages;
}
