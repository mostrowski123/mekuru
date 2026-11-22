// Rewrites an EPUB with furigana baked into its XHTML so the result renders
// on external e-readers. Pure Dart (no Flutter imports) and safe to run
// inside a `MecabService.runOffIsolate` worker.
//
// Mode semantics mirror the reader's FuriganaMode:
// - book: the original file, byte for byte.
// - hide: all existing ruby stripped, nothing generated.
// - all: ruby generated for kanji words; authored ruby kept.
// - aboveLevel: like all, but the JLPT filter (the generator's skipToken)
//   also wins over the publisher: authored ruby whose base is entirely at
//   or below the level is stripped (stripRubyWhere).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/core/utils/xhtml.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/furigana_generator.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

const _skippedSubtrees = {'ruby', 'rt', 'rp', 'script', 'style', 'head'};

/// Text nodes eligible for furigana: outside ruby/script/style/head subtrees
/// and containing at least one kanji. Mirrors the reader's TreeWalker filter
/// in reader_bridge.js (which prunes the same subtrees) so export and
/// on-screen furigana agree.
List<XmlText> furiganaTargets(XmlDocument doc) {
  final targets = <XmlText>[];
  void visit(XmlNode node) {
    for (final child in node.children) {
      if (child is XmlElement) {
        if (_skippedSubtrees.contains(child.name.local.toLowerCase())) {
          continue;
        }
        visit(child);
      } else if (child is XmlText &&
          child.value.runes.any(isKanjiForFurigana)) {
        targets.add(child);
      }
    }
  }

  visit(doc);
  return targets;
}

/// Replaces [node] with the markup described by [segments]
/// (FuriganaGenerator's `{t, f?}` list): plain text for bare segments,
/// `<ruby>t<rt>f</rt></ruby>` for annotated ones. The ruby element gets no
/// xmlns attribute — an unprefixed name inherits the XHTML default
/// namespace declared on `<html>`.
void spliceRuby(XmlText node, List<Map<String, Object?>> segments) {
  final parent = node.parent!;

  final replacements = <XmlNode>[];
  for (final segment in segments) {
    final text = segment['t'];
    if (text is! String) continue;
    final furigana = segment['f'];
    if (furigana is String) {
      replacements.add(
        XmlElement(XmlName('ruby'), const [], [
          XmlText(text),
          XmlElement(XmlName('rt'), const [], [XmlText(furigana)]),
        ]),
      );
    } else {
      replacements.add(XmlText(text));
    }
  }

  final index = parent.children.indexOf(node);
  parent.children.removeAt(index);
  parent.children.insertAll(index, replacements);
}

/// [xhtml] with every `<ruby>` unwrapped to its base text (rt/rp dropped,
/// rb unwrapped). Null when the document has no ruby or does not parse —
/// the caller keeps the original entry.
String? stripRubyXhtml(String xhtml) {
  final doc = parseXhtml(xhtml);
  if (doc == null) return null;

  final rubies = doc.findAllElements('ruby').toList();
  if (rubies.isEmpty) return null;

  for (final ruby in rubies) {
    if (ruby.parent == null) continue;
    _unwrapRuby(ruby, _rubyBaseNodes(ruby));
  }
  return doc.toXmlString();
}

/// Text of [ruby]'s base content (children minus rt/rp), without copying.
String _rubyBaseText(XmlElement ruby) {
  final buffer = StringBuffer();
  for (final child in ruby.children) {
    if (child is XmlElement) {
      final tag = child.name.local.toLowerCase();
      if (tag == 'rt' || tag == 'rp') continue;
      buffer.write(child.innerText);
    } else {
      // value covers text/CDATA leaves (innerText is descendants-only and
      // empty for them).
      buffer.write(child.value ?? child.innerText);
    }
  }
  return buffer.toString();
}

/// Copies of [ruby]'s base content: children minus rt/rp, with rb unwrapped.
List<XmlNode> _rubyBaseNodes(XmlElement ruby) {
  final base = <XmlNode>[];
  for (final child in ruby.children) {
    if (child is XmlElement) {
      final tag = child.name.local.toLowerCase();
      if (tag == 'rt' || tag == 'rp') continue;
      if (tag == 'rb') {
        base.addAll(child.children.map((n) => n.copy()));
        continue;
      }
    }
    base.add(child.copy());
  }
  return base;
}

/// Replaces [ruby] with [base] in its parent's child list.
void _unwrapRuby(XmlElement ruby, List<XmlNode> base) {
  final parent = ruby.parent!;
  final index = parent.children.indexOf(ruby);
  parent.children.removeAt(index);
  parent.children.insertAll(index, base);
}

/// [xhtml] with generated ruby spliced in. Null when the document does not
/// parse, nothing changed, or the tokenizer went away (the caller
/// keeps the original entry — [buildFuriganaEpub] probes tokenizer
/// availability up front so that last case cannot silently skip a book).
///
/// [stripRubyWhere] (aboveLevel mode) unwraps authored ruby whose base text
/// matches, before annotation, so the JLPT filter also wins over the
/// publisher's own ruby.
Future<String?> annotateXhtml(
  String xhtml,
  FuriganaGenerator generator, {
  bool Function(String baseText)? stripRubyWhere,
}) async {
  final doc = parseXhtml(xhtml);
  if (doc == null) return null;

  // Unwrapped base nodes are excluded from annotation below: the predicate
  // already proved they contain nothing above the level, so tokenizing them
  // would be a guaranteed no-op per stripped ruby.
  final strippedBases = <XmlNode>{};
  if (stripRubyWhere != null) {
    for (final ruby in doc.findAllElements('ruby').toList()) {
      if (ruby.parent == null) continue;
      if (!stripRubyWhere(_rubyBaseText(ruby))) continue;
      final base = _rubyBaseNodes(ruby);
      _unwrapRuby(ruby, base);
      strippedBases.addAll(base);
    }
  }
  final stripped = strippedBases.isNotEmpty;

  final targets = furiganaTargets(
    doc,
  ).where((t) => !strippedBases.contains(t)).toList();
  if (targets.isEmpty) return stripped ? doc.toXmlString() : null;

  // One batch per document: the reader's batch-of-50 exists only to bound
  // webview bridge payloads, which don't apply in-process.
  final annotations = await generator.generate([
    for (final target in targets) target.value,
  ]);
  if (annotations == null) return null;

  var changed = false;
  for (var i = 0; i < targets.length && i < annotations.length; i++) {
    final segments = (annotations[i]['segments']! as List)
        .cast<Map<String, Object?>>();
    if (!segments.any((s) => s['f'] != null)) continue;
    spliceRuby(targets[i], segments);
    changed = true;
  }
  if (!changed && !stripped) return null;

  // No pretty-printing: it would inject whitespace into Japanese text runs
  // and around inline ruby.
  return doc.toXmlString();
}

/// [entry] decompressed without caching it on the entry. A cached entry
/// must not pass through to the encoder: it deflates the raw stream a second
/// time while keeping the original sizes, which corrupts it.
String _peekText(ArchiveFile entry) =>
    utf8.decode(entry.rawContent!.getStream().toUint8List());

/// Zip entry names of the OPF manifest's XHTML content documents.
Set<String> _contentDocumentNames(Archive archive) {
  final container = archive.findFile('META-INF/container.xml');
  if (container == null) return const {};
  final containerXml = parseXhtml(_peekText(container));
  if (containerXml == null) return const {};
  final opfPath = EpubParser.extractOpfPathFromXml(containerXml);
  if (opfPath == null) return const {};

  final opfEntry = archive.findFile(opfPath);
  if (opfEntry == null) return const {};
  final opfXml = parseXhtml(_peekText(opfEntry));
  if (opfXml == null) return const {};

  final opfDir = p.posix.dirname(opfPath);
  final names = <String>{};
  for (final item in opfXml.findAllElements('item')) {
    if (item.getAttribute('media-type') != 'application/xhtml+xml') continue;
    final href = item.getAttribute('href');
    if (href == null) continue;
    final name = resolveEpubHref(
      opfDir,
      href,
      exists: (path) => archive.findFile(path) != null,
    );
    if (name != null) names.add(name);
  }
  return names;
}

/// Writes the EPUB at [epubPath], rebuilt according to [mode], to [outPath].
/// [generator] is required for the annotating modes; [stripRubyWhere]
/// carries aboveLevel's authored-ruby policy (see [authoredRubyStripFor])
/// and must be derived from the same mode/level as [generator]. Returns
/// false, having written nothing, iff MeCab cannot come up; throws on
/// unreadable/corrupt input.
///
/// Works entry by entry, file to file: memory holds one chapter at a time,
/// whatever the size of the book.
Future<bool> writeFuriganaEpub(
  String epubPath,
  String outPath, {
  required FuriganaMode mode,
  FuriganaGenerator? generator,
  bool Function(String baseText)? stripRubyWhere,
}) async {
  if (mode == FuriganaMode.book) {
    await File(epubPath).copy(outPath);
    return true;
  }

  // One upfront availability probe; after it succeeds the per-chapter code
  // can treat the generator as infallible. False is the load-bearing "MeCab
  // could not come up" signal — never silently export unannotated.
  if (mode != FuriganaMode.hide &&
      await generator!.generate(const []) == null) {
    return false;
  }

  final input = InputFileStream(epubPath);
  OutputFileStream? output;
  try {
    final archive = ZipDecoder().decodeStream(input);
    final contentDocs = _contentDocumentNames(archive);
    // autoClose would close each entry's window, and they all share the
    // input's one file handle.
    final zip = ZipEncoder()..startEncode(output = OutputFileStream(outPath));
    // A valid EPUB has `mimetype` first and uncompressed. Always rebuild it:
    // one code path, and no reliance on the source entry's STORED flag.
    const mimetype = 'application/epub+zip';
    zip.add(
      ArchiveFile.noCompress(
        'mimetype',
        mimetype.length,
        utf8.encode(mimetype),
      ),
      autoClose: false,
    );
    for (final entry in archive.files) {
      if (entry.name == 'mimetype') continue;
      // Everything but the chapters passes through as stored in the
      // source, streamed from the input file: deflated entries keep their
      // raw stream, STORED ones stay stored. Nothing here has cached its
      // content (see _peekText), so none is deflated twice.
      if (!entry.isFile || !contentDocs.contains(entry.name)) {
        zip.add(entry, autoClose: false);
        continue;
      }
      final originalBytes = entry.content;
      entry.clear();
      final xhtml = utf8.decode(originalBytes, allowMalformed: true);
      final rewritten = mode == FuriganaMode.hide
          ? stripRubyXhtml(xhtml)
          : await annotateXhtml(
              xhtml,
              generator!,
              stripRubyWhere: stripRubyWhere,
            );
      zip.add(
        ArchiveFile.bytes(
          entry.name,
          rewritten == null ? originalBytes : utf8.encode(rewritten),
        ),
        autoClose: false,
      );
    }
    zip.endEncode();
  } finally {
    await output?.close();
    await input.close();
  }
  return true;
}

/// [writeFuriganaEpub]'s output as bytes, for tests. The app never calls
/// this: it holds the whole book in memory.
Future<Uint8List?> buildFuriganaEpub(
  String epubPath, {
  required FuriganaMode mode,
  FuriganaGenerator? generator,
  bool Function(String baseText)? stripRubyWhere,
}) async {
  final dir = await Directory.systemTemp.createTemp('furigana_export_');
  try {
    final outPath = p.join(dir.path, 'out.epub');
    final written = await writeFuriganaEpub(
      epubPath,
      outPath,
      mode: mode,
      generator: generator,
      stripRubyWhere: stripRubyWhere,
    );
    return written ? await File(outPath).readAsBytes() : null;
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Worker-isolate entry point: builds the right generator for [mode] and
/// writes the rewritten EPUB to [outPath] (see [writeFuriganaEpub]). Capture
/// only this call in the isolate closure — its arguments are all sendable.
Future<bool> writeFuriganaEpubForMode(
  String epubPath,
  String outPath, {
  required FuriganaMode mode,
  required int jlptLevel,
  Set<int> knownKanji = const {},
}) {
  // The generator is unused by the book/hide modes, so it is built
  // unconditionally rather than branching on the mode.
  return writeFuriganaEpub(
    epubPath,
    outPath,
    mode: mode,
    generator: furiganaGeneratorFor(mode, jlptLevel, knownKanji: knownKanji),
    stripRubyWhere: authoredRubyStripFor(
      mode,
      jlptLevel,
      knownKanji: knownKanji,
    ),
  );
}
