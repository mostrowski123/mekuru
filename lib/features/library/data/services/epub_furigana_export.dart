// Rewrites an EPUB with furigana baked into its XHTML so the result renders
// on external e-readers. Pure Dart (no Flutter imports) and safe to run
// inside a `MecabService.runOffIsolate` worker.
//
// Mode semantics mirror the reader's FuriganaMode:
// - book: the original file, byte for byte.
// - hide: all existing ruby stripped, nothing generated.
// - all / aboveLevel: ruby generated for kanji words (the JLPT filter lives
//   in the generator's skipToken).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/core/utils/jlpt_kanji_levels.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/furigana_generator.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Thrown internally when the tokenizer cannot come up; surfaces as a null
/// return from [buildFuriganaEpub] so callers can show "furigana
/// unavailable" instead of silently exporting an unannotated book.
class _TokenizerUnavailable implements Exception {
  const _TokenizerUnavailable();
}

const _skippedAncestors = {'ruby', 'rt', 'rp', 'script', 'style', 'head'};

/// Text nodes eligible for furigana: outside ruby/script/style/head subtrees
/// and containing at least one kanji. Mirrors the reader's TreeWalker filter
/// in reader_bridge.js so export and on-screen furigana agree.
List<XmlText> furiganaTargets(XmlDocument doc) {
  final targets = <XmlText>[];
  for (final node in doc.descendants.whereType<XmlText>()) {
    if (!node.value.runes.any(isKanjiForFurigana)) continue;
    final blocked = node.ancestorElements.any(
      (element) => _skippedAncestors.contains(element.name.local.toLowerCase()),
    );
    if (!blocked) targets.add(node);
  }
  return targets;
}

/// Replaces [node] with the markup described by [segments]
/// (FuriganaGenerator's `{t, f?}` list): plain text for bare segments,
/// `<ruby>t<rt>f</rt></ruby>` for annotated ones. The ruby element gets no
/// xmlns attribute — an unprefixed name inherits the XHTML default
/// namespace declared on `<html>`.
void spliceRuby(XmlText node, List<dynamic> segments) {
  final parent = node.parent;
  if (parent == null) return;

  final replacements = <XmlNode>[];
  for (final segment in segments) {
    if (segment is! Map) continue;
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
    final parent = ruby.parent;
    if (parent == null) continue;
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
    final index = parent.children.indexOf(ruby);
    parent.children.removeAt(index);
    parent.children.insertAll(index, base);
  }
  return doc.toXmlString();
}

/// [xhtml] with generated ruby spliced in. Null when the document does not
/// parse or nothing was annotated (caller keeps the original entry). Throws
/// [_TokenizerUnavailable] when the generator reports MeCab down.
Future<String?> annotateXhtml(String xhtml, FuriganaGenerator generator) async {
  final doc = _parseXhtml(xhtml);
  if (doc == null) return null;

  final targets = furiganaTargets(doc);
  if (targets.isEmpty) return null;

  // One batch per document: the reader's batch-of-50 exists only to bound
  // webview bridge payloads, which don't apply in-process.
  final annotations = await generator.generate([
    for (final target in targets) target.value,
  ]);
  if (annotations == null) throw const _TokenizerUnavailable();

  var changed = false;
  for (var i = 0; i < targets.length && i < annotations.length; i++) {
    final segments = annotations[i]['segments'];
    if (segments is! List) continue;
    final hasRuby = segments.any((s) => s is Map && s['f'] != null);
    if (!hasRuby) continue;
    spliceRuby(targets[i], segments);
    changed = true;
  }
  if (!changed) return null;

  // No pretty-printing: it would inject whitespace into Japanese text runs
  // and around inline ruby.
  return doc.toXmlString();
}

/// Zip entry names of the OPF manifest's XHTML content documents.
Set<String> _contentDocumentNames(Archive archive) {
  final container = archive.findFile('META-INF/container.xml');
  if (container == null) return const {};
  final XmlDocument containerXml;
  try {
    containerXml = XmlDocument.parse(utf8.decode(container.readBytes()!));
  } on XmlException {
    return const {};
  }
  final rootfiles = containerXml.findAllElements('rootfile');
  if (rootfiles.isEmpty) return const {};
  final opfPath = rootfiles.first.getAttribute('full-path');
  if (opfPath == null) return const {};

  final opfEntry = archive.findFile(opfPath);
  if (opfEntry == null) return const {};
  final XmlDocument opfXml;
  try {
    opfXml = XmlDocument.parse(utf8.decode(opfEntry.readBytes()!));
  } on XmlException {
    return const {};
  }

  final opfDir = p.posix.dirname(opfPath);
  final names = <String>{};
  for (final item in opfXml.findAllElements('item')) {
    if (item.getAttribute('media-type') != 'application/xhtml+xml') continue;
    final href = item.getAttribute('href');
    if (href == null) continue;
    final decoded = Uri.decodeFull(href);
    names.add(
      p.posix.normalize(
        opfDir == '.' ? decoded : p.posix.join(opfDir, decoded),
      ),
    );
  }
  return names;
}

/// The EPUB at [epubPath] rebuilt according to [mode]. [generator] is
/// required for the annotating modes. Returns null iff MeCab cannot come
/// up; throws on unreadable/corrupt input.
Future<Uint8List?> buildFuriganaEpub(
  String epubPath, {
  required FuriganaMode mode,
  FuriganaGenerator? generator,
}) async {
  final original = await File(epubPath).readAsBytes();
  if (mode == FuriganaMode.book) return original;

  final archive = ZipDecoder().decodeBytes(original);
  final contentDocs = _contentDocumentNames(archive);

  final out = Archive();
  try {
    for (final entry in archive.files) {
      if (!entry.isFile || !contentDocs.contains(entry.name)) {
        // Untouched entries are re-added as decoded objects, which the zip
        // encoder passes through without re-compressing — images keep their
        // bytes and `mimetype` stays STORED.
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
          : await annotateXhtml(xhtml, generator!);
      out.addFile(
        ArchiveFile.bytes(
          entry.name,
          rewritten == null ? originalBytes : utf8.encode(rewritten),
        ),
      );
    }
  } on _TokenizerUnavailable {
    return null;
  }

  // A valid EPUB has `mimetype` first and uncompressed; repair if the
  // source was sloppy.
  if (out.files.isEmpty || out.files.first.name != 'mimetype') {
    out.files.removeWhere((f) => f.name == 'mimetype');
    const mimetype = 'application/epub+zip';
    out.files.insert(
      0,
      ArchiveFile.noCompress(
        'mimetype',
        mimetype.length,
        utf8.encode(mimetype),
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
  final generator = switch (mode) {
    FuriganaMode.all => const FuriganaGenerator(MecabFuriganaTokenizer()),
    FuriganaMode.aboveLevel => FuriganaGenerator(
      const MecabFuriganaTokenizer(),
      skipToken: (token) =>
          !wordNeedsFuriganaAboveLevel(token.surface, jlptLevel),
    ),
    _ => null,
  };
  return buildFuriganaEpub(epubPath, mode: mode, generator: generator);
}
