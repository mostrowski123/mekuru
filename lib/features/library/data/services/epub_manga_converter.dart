import 'dart:io';

import 'package:mekuru/core/utils/xhtml.dart';
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

/// The spine of the extracted EPUB at [contentDir], in order: each
/// document's root-relative path, with the spread side its itemref declares
/// (`page-spread-*`, with or without the `rendition:` prefix). Itemrefs that
/// name no manifest item are left out. Null when there is no readable OPF or
/// spine.
Future<List<({String path, MangaPageSpread? spread})>?> readEpubSpine(
  String contentDir,
) async {
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

  final opfDir = p.posix.dirname(opfPath);
  return [
    for (final itemref in spines.first.findElements('itemref'))
      if (manifestHrefById[itemref.getAttribute('idref')] case final href?)
        if (resolveEpubHref(opfDir, href) case final path?)
          (path: path, spread: _spreadOf(itemref.getAttribute('properties'))),
  ];
}

MangaPageSpread? _spreadOf(String? properties) => MangaPageSpread.values
    .asNameMap()[_spreadProperty.firstMatch(properties ?? '')?.group(1)];

final _spreadProperty = RegExp(r'(?:^|\s)(?:rendition:)?page-spread-(\w+)');

/// Scans an extracted EPUB (`content/` directory) and, when (nearly) every
/// spine document resolves to exactly one image, returns those images'
/// absolute paths in spine order, de-duplicated, each with its declared
/// spread (the first one declared, when several docs show the same image).
/// Returns null when the book does not look like a manga.
///
/// Read-only: safe to call without any cleanup obligation.
Future<List<({String path, MangaPageSpread? spread})>?> _planConversion(
  String contentDir,
) async {
  final spine = await readEpubSpine(contentDir);
  if (spine == null || spine.isEmpty) return null;

  // Insertion-ordered: an image keeps its first place in the spine.
  final spreadByImage = <String, MangaPageSpread?>{};
  var imageDocCount = 0;
  for (final doc in spine) {
    final image = await singleImageOf(contentDir, doc.path);
    if (image == null) continue;
    // A duplicate (the cover XHTML and a page pointing at the same file)
    // still counts as an image doc for eligibility, but yields one page.
    imageDocCount++;
    spreadByImage[image] ??= doc.spread;
  }

  final eligible =
      spreadByImage.length >= 3 && imageDocCount / spine.length >= 0.9;
  if (!eligible) return null;
  return [
    for (final MapEntry(key: image, value: spread) in spreadByImage.entries)
      (path: p.join(contentDir, image), spread: spread),
  ];
}

/// Every image of the spine document at [docPath], in document order: each
/// `img` and each `image` inside an `svg` (what the reader bridge counts as
/// `img, svg image`), as a root-relative path, or null when its reference is
/// unusable. Empty when the document can't be read or parsed.
Future<List<String?>> epubDocImages(String contentDir, String docPath) async {
  final XmlDocument? doc;
  try {
    doc = parseXhtml(await File(p.join(contentDir, docPath)).readAsString());
  } on Exception {
    return const [];
  }
  if (doc == null) return const [];

  final docDir = p.posix.dirname(docPath);
  String? resolve(String? ref) =>
      ref == null ? null : resolveEpubHref(docDir, ref);
  return [
    for (final el in doc.descendants.whereType<XmlElement>())
      if (el.localName == 'img')
        resolve(el.getAttribute('src'))
      // SVG-wrapped pages: match the href attribute by local name so both
      // xlink:href and plain href are caught.
      else if (el.localName == 'image' &&
          el.ancestors.any((a) => a is XmlElement && a.localName == 'svg'))
        resolve(
          el.attributes.where((a) => a.name.local == 'href').firstOrNull?.value,
        ),
  ];
}

/// Returns the root-relative path of the single page image referenced by the
/// spine document at [docPath], or null when the doc is not an
/// exactly-one-image page.
Future<String?> singleImageOf(String contentDir, String docPath) async {
  final resolved = <String>{};
  for (final rel in await epubDocImages(contentDir, docPath)) {
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
  final plan = await _planConversion(contentDir);
  if (plan == null) {
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
    for (var i = 0; i < plan.length; i++) {
      final source = plan[i].path;
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
        spread: plan[i].spread,
      ),
    );
  }
  return pages;
}
