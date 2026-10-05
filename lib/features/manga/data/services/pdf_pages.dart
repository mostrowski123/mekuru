import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:image/image.dart' as img;
import 'package:mekuru/features/manga/data/services/pdf_text_blocks.dart';
import 'package:pdfrx/pdfrx.dart';

/// A PDF opened for import: each page rendered to a JPEG, with the glyphs
/// drawn on it. PDFium (through pdfrx) on both platforms, so Android and
/// iOS see the same text layer.
class PdfPages {
  PdfPages._(this._document);

  final PdfDocument _document;

  /// Pixels per page at most (an A4 page 1240 px wide has 1.8 million): a
  /// very tall page renders narrower instead of exhausting memory.
  static const _maxPixels = 4000000;

  /// Opens [path]. Throws [PdfPasswordException] for an encrypted PDF and
  /// [PdfException] for one PDFium cannot read.
  static Future<PdfPages> open(String path) async {
    await pdfrxFlutterInitialize();
    return PdfPages._(await PdfDocument.openFile(path));
  }

  int get pageCount => _document.pages.length;

  /// Renders page [index] (0-based) at most [widthPx] wide and returns its
  /// size and glyphs, boxed in the image's pixels. The JPEG is encoded and
  /// written to [outPath] in another isolate; [written] completes once it
  /// is on disk.
  Future<({int width, int height, List<PdfGlyph> glyphs, Future<void> written})>
  render(int index, {required int widthPx, required String outPath}) async {
    final page = _document.pages[index];
    final scale = math.min(
      widthPx / page.width,
      math.sqrt(_maxPixels / (page.width * page.height)),
    );
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) throw const PdfException('page did not render');
    final (width, height) = (image.width, image.height);
    // pixels views native memory that dispose() frees: copy it once, into a
    // buffer the encoding isolate takes over without another copy.
    final pixels = TransferableTypedData.fromList([image.pixels]);
    image.dispose();
    final written = Isolate.run(
      () => _writeJpeg(pixels, width, height, outPath),
    );

    final text = await page.loadText();
    final glyphs = <PdfGlyph>[];
    if (text != null) {
      final size = Size(width.toDouble(), height.toDouble());
      final count = math.min(text.charRects.length, text.fullText.length);
      for (var i = 0; i < count; i++) {
        // PDF space to the image's pixels, turned with the page's /Rotate.
        final r = text.charRects[i].toRect(page: page, scaledPageSize: size);
        glyphs.add(
          PdfGlyph(text.fullText[i], r.left, r.top, r.right, r.bottom),
        );
      }
    }
    return (width: width, height: height, glyphs: glyphs, written: written);
  }

  Future<void> close() => _document.dispose();
}

Future<void> _writeJpeg(
  TransferableTypedData pixels,
  int width,
  int height,
  String path,
) => File(path).writeAsBytes(
  img.encodeJpg(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.materialize(),
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    ),
    quality: 85,
  ),
);
