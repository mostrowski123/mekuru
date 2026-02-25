import 'dart:ui' show Rect;

import '../../../reader/data/services/mecab_service.dart';
import '../models/mokuro_models.dart';

/// Segments mokuro OCR text blocks into individual words using MeCab,
/// and computes approximate bounding boxes for each word based on
/// line coordinates and proportional character positioning.
class MokuroWordSegmenter {
  const MokuroWordSegmenter._();

  /// Segment all text blocks across all pages.
  /// Returns new pages with populated [MokuroWord] lists.
  static Future<List<MokuroPage>> segmentAllPages(
    List<MokuroPage> pages,
  ) async {
    final result = <MokuroPage>[];
    for (final page in pages) {
      if (page.blocks.isEmpty) {
        result.add(page);
        continue;
      }
      final newBlocks = <MokuroTextBlock>[];
      for (int blockIdx = 0; blockIdx < page.blocks.length; blockIdx++) {
        final block = page.blocks[blockIdx];
        final words = _segmentBlock(block, blockIdx);
        newBlocks.add(block.copyWith(words: words));
      }
      result.add(page.copyWith(blocks: newBlocks));
    }
    return result;
  }

  /// Segment a single text block into words with bounding boxes.
  static List<MokuroWord> _segmentBlock(MokuroTextBlock block, int blockIdx) {
    final words = <MokuroWord>[];
    final mecab = MecabService.instance;

    // Process each line independently
    for (int lineIdx = 0; lineIdx < block.lines.length; lineIdx++) {
      final lineText = block.lines[lineIdx];
      if (lineText.isEmpty) continue;

      // Skip lines with no matching coordinate data
      if (lineIdx >= block.linesCoords.length) continue;
      final lineQuad = block.linesCoords[lineIdx];
      if (lineQuad.length < 4) continue;

      // Tokenize the line text
      final surfaces = mecab.tokenize(lineText);

      // Build words with bounding boxes
      int charPos = 0;
      for (final surface in surfaces) {
        final charStart = charPos;
        final charEnd = charPos + surface.length;

        // Get dictionary form and reading via identifyWordWithContext
        String? dictForm;
        String? reading;
        final identification =
            mecab.identifyWordWithContext(lineText, charStart);
        if (identification != null) {
          dictForm = identification.result.dictionaryForm;
          reading = identification.result.reading;
        }

        // Compute bounding box from line quad
        final bbox = _computeWordBbox(
          lineQuad,
          lineText.length,
          charStart,
          charEnd,
          block.vertical,
        );

        if (bbox != null && surface.trim().isNotEmpty) {
          words.add(MokuroWord(
            surface: surface,
            dictionaryForm: dictForm,
            reading: reading,
            boundingBox: bbox,
            blockIndex: blockIdx,
            lineIndex: lineIdx,
            charStartInLine: charStart,
            charEndInLine: charEnd,
          ));
        }

        charPos = charEnd;
      }
    }

    return words;
  }

  /// Compute a word's bounding box within a line quad.
  ///
  /// A line quad has 4 points: [topLeft, topRight, bottomRight, bottomLeft]
  /// in mokuro's coordinate system.
  ///
  /// For **vertical text**, characters are stacked top-to-bottom.
  /// For **horizontal text**, characters flow left-to-right.
  ///
  /// We divide the line's extent proportionally by character count.
  static Rect? _computeWordBbox(
    List<List<double>> quad,
    int totalChars,
    int charStart,
    int charEnd,
    bool vertical,
  ) {
    if (totalChars == 0 || quad.length < 4) return null;

    // quad points: [topLeft, topRight, bottomRight, bottomLeft]
    final tl = quad[0]; // top-left [x, y]
    final tr = quad[1]; // top-right [x, y]
    final br = quad[2]; // bottom-right [x, y]
    final bl = quad[3]; // bottom-left [x, y]

    final startFrac = charStart / totalChars;
    final endFrac = charEnd / totalChars;

    if (vertical) {
      // Vertical text: characters flow top-to-bottom.
      // Interpolate Y along the left and right edges.
      final leftTop = _lerp2(tl, bl, startFrac);
      final leftBottom = _lerp2(tl, bl, endFrac);
      final rightTop = _lerp2(tr, br, startFrac);
      final rightBottom = _lerp2(tr, br, endFrac);

      final left = leftTop[0] < rightTop[0] ? leftTop[0] : rightTop[0];
      final right = leftTop[0] > rightTop[0] ? leftTop[0] : rightTop[0];
      final top = leftTop[1] < rightTop[1] ? leftTop[1] : rightTop[1];
      final bottom =
          leftBottom[1] > rightBottom[1] ? leftBottom[1] : rightBottom[1];

      return Rect.fromLTRB(left, top, right, bottom);
    } else {
      // Horizontal text: characters flow left-to-right.
      // Interpolate X along the top and bottom edges.
      final topStart = _lerp2(tl, tr, startFrac);
      final topEnd = _lerp2(tl, tr, endFrac);
      final bottomStart = _lerp2(bl, br, startFrac);
      final bottomEnd = _lerp2(bl, br, endFrac);

      final left = topStart[0] < bottomStart[0] ? topStart[0] : bottomStart[0];
      final right = topEnd[0] > bottomEnd[0] ? topEnd[0] : bottomEnd[0];
      final top = topStart[1] < topEnd[1] ? topStart[1] : topEnd[1];
      final bottom =
          bottomStart[1] > bottomEnd[1] ? bottomStart[1] : bottomEnd[1];

      return Rect.fromLTRB(left, top, right, bottom);
    }
  }

  /// Linear interpolation between two 2D points.
  static List<double> _lerp2(List<double> a, List<double> b, double t) {
    return [
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t,
    ];
  }
}
