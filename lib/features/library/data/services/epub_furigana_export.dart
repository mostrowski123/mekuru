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

import 'package:archive/archive.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
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

XmlDocument? _parseXhtml(String xhtml) {
  try {
    // The html5 entity mapping is mandatory: the default XML mapping leaves
    // named entities like &nbsp; undecoded, and re-encoding then turns them
    // into visible "&amp;nbsp;" text.
    return XmlDocument.parse(
      xhtml,
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
  } on XmlException {
    return null;
  }
}

/// [xhtml] with every `<ruby>` unwrapped to its base text (rt/rp dropped,
/// rb unwrapped). Null when the document has no ruby or does not parse —
/// the caller keeps the original entry.
String? stripRubyXhtml(String xhtml) {
  final doc = _parseXhtml(xhtml);
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
  final doc = _parseXhtml(xhtml);
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

/// Zip entry names of the OPF manifest's XHTML content documents.
Set<String> _contentDocumentNames(Archive archive) {
  final container = archive.findFile('META-INF/container.xml');
  if (container == null) return const {};
  final containerXml = _parseXhtml(utf8.decode(container.readBytes()!));
  if (containerXml == null) return const {};
  final opfPath = EpubParser.extractOpfPathFromXml(containerXml);
  if (opfPath == null) return const {};

  final opfEntry = archive.findFile(opfPath);
  if (opfEntry == null) return const {};
  final opfXml = _parseXhtml(utf8.decode(opfEntry.readBytes()!));
  if (opfXml == null) return const {};

  final opfDir = p.posix.dirname(opfPath);
  final names = <String>{};
  for (final item in opfXml.findAllElements('item')) {
    if (item.getAttribute('media-type') != 'application/xhtml+xml') continue;
    final href = item.getAttribute('href');
    if (href == null) continue;
    names.add(p.posix.normalize(p.posix.join(opfDir, Uri.decodeFull(href))));
  }
  return names;
}

/// The EPUB at [epubPath] rebuilt according to [mode]. [generator] is
/// required for the annotating modes; [stripRubyWhere] carries aboveLevel's
/// authored-ruby policy (see [authoredRubyStripFor]) and must be derived
/// from the same mode/level as [generator]. Returns null iff MeCab cannot
/// come up; throws on unreadable/corrupt input.
Future<Uint8List?> buildFuriganaEpub(
  String epubPath, {
  required FuriganaMode mode,
  FuriganaGenerator? generator,
  bool Function(String baseText)? stripRubyWhere,
}) async {
  final original = await File(epubPath).readAsBytes();
  if (mode == FuriganaMode.book) return original;

  final archive = ZipDecoder().decodeBytes(original);

  // One upfront availability probe; after it succeeds the per-chapter code
  // can treat the generator as infallible. Null is the load-bearing "MeCab
  // could not come up" signal — never silently export unannotated.
  if (mode != FuriganaMode.hide &&
      await generator!.generate(const []) == null) {
    return null;
  }

  final contentDocs = _contentDocumentNames(archive);
  final out = Archive();
  // A valid EPUB has `mimetype` first and uncompressed. Always rebuild it:
  // one code path, and no reliance on the encoder's pass-through keeping
  // the source entry's STORED flag.
  const mimetype = 'application/epub+zip';
  out.addFile(
    ArchiveFile.noCompress('mimetype', mimetype.length, utf8.encode(mimetype)),
  );
  for (final entry in archive.files) {
    if (entry.name == 'mimetype') continue;
    if (!entry.isFile || !contentDocs.contains(entry.name)) {
      // Untouched entries are re-added as decoded objects, which the zip
      // encoder passes through without re-compressing — images keep their
      // bytes.
      out.addFile(entry);
      continue;
    }
    // Once readBytes() has consumed a decoder entry it must not be
    // re-added for pass-through — re-encoding it corrupts the data. Keep
    // the bytes we already read instead.
    final originalBytes = entry.readBytes()!;
    final xhtml = utf8.decode(originalBytes, allowMalformed: true);
    final rewritten = mode == FuriganaMode.hide
        ? stripRubyXhtml(xhtml)
        : await annotateXhtml(
            xhtml,
            generator!,
            stripRubyWhere: stripRubyWhere,
          );
    out.addFile(
      ArchiveFile.bytes(
        entry.name,
        rewritten == null ? originalBytes : utf8.encode(rewritten),
      ),
    );
  }

  return ZipEncoder().encodeBytes(out);
}

/// Worker-isolate entry point: builds the right generator for [mode] and
/// rewrites the EPUB. Capture only this call in the isolate closure — its
/// arguments are all sendable.
Future<Uint8List?> buildFuriganaEpubForMode(
  String epubPath, {
  required FuriganaMode mode,
  required int jlptLevel,
}) {
  // The generator is unused by the book/hide modes, so it is built
  // unconditionally rather than branching on the mode.
  return buildFuriganaEpub(
    epubPath,
    mode: mode,
    generator: furiganaGeneratorFor(mode, jlptLevel),
    stripRubyWhere: authoredRubyStripFor(mode, jlptLevel),
  );
}
