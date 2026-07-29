import '../../../reader/data/services/mecab_service.dart';
import '../models/mokuro_models.dart';
import 'mokuro_block_geometry.dart';

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
    // Bring MeCab up before segmenting; without it we'd produce no words at
    // all (or, before tokenize() stopped falling back to whole-line tokens,
    // cache line-sized pseudo-words). If init fails, return the pages
    // untouched so callers cache nothing new and the reader's self-heal
    // path retries on a later load. Segmentation only needs IPADIC; the
    // flag only decides anything in background isolates — on the main
    // isolate the startup warmup has already fixed the dictionary policy.
    final ready = await MecabService.instance.ensureInitialized(
      upgradeToEnhanced: false,
    );
    if (!ready) return pages;

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
        final identification = mecab.identifyWordWithContext(
          lineText,
          charStart,
        );
        if (identification != null) {
          dictForm = identification.result.dictionaryForm;
          reading = identification.result.reading;
        }

        // Compute bounding box from line quad
        final bbox = lineCharRangeRect(
          quad: lineQuad,
          lineLength: lineText.length,
          charStart: charStart,
          charEnd: charEnd,
          vertical: block.vertical,
        );

        if (bbox != null && surface.trim().isNotEmpty) {
          words.add(
            MokuroWord(
              surface: surface,
              dictionaryForm: dictForm,
              reading: reading,
              boundingBox: bbox,
              blockIndex: blockIdx,
              lineIndex: lineIdx,
              charStartInLine: charStart,
              charEndInLine: charEnd,
            ),
          );
        }

        charPos = charEnd;
      }
    }

    return words;
  }
}
