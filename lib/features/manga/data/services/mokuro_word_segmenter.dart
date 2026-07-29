import '../../../reader/data/services/mecab_service.dart';
import '../models/mokuro_models.dart';
import 'mokuro_block_geometry.dart';
import 'mokuro_segmentation_repair.dart';

/// Segments mokuro OCR text blocks into individual words using MeCab,
/// and computes approximate bounding boxes for each word based on
/// line coordinates and proportional character positioning.
class MokuroWordSegmenter {
  const MokuroWordSegmenter._();

  /// Whether [pages] need a (re-)segmentation run before tap lookups behave:
  /// words missing or broken, or word boxes cut by a different dictionary
  /// than this session's tap-time lookups tokenize with.
  ///
  /// Missing/broken words are worth waiting for MeCab init. The dictionary
  /// mismatch is only checked once MeCab is already up: the check needs the
  /// session layout, and blocking a healthy-cache open on init isn't worth
  /// a refinement that self-corrects on a later open. When a mismatch
  /// against the expected dictionary is found, any in-flight UniDic-lite
  /// upgrade is settled first, so a failed upgrade cannot trigger a
  /// pointless re-segmentation.
  static Future<bool> needsResegmentation(List<MokuroPage> pages) async {
    final mecab = MecabService.instance;
    if (pagesNeedWordSegmentation(pages)) {
      return mecab.ensureInitialized();
    }
    if (!mecab.isInitialized) return false;
    final expectedLabel = mecab.expectedLayout.label;
    if (!pagesSegmentedWithDifferentDictionary(pages, expectedLabel)) {
      return false;
    }
    final settledLabel = (await mecab.settledLayout()).label;
    return settledLabel == expectedLabel ||
        pagesSegmentedWithDifferentDictionary(pages, settledLabel);
  }

  /// Segment all text blocks across all pages.
  /// Returns new pages with populated [MokuroWord] lists.
  ///
  /// With [onlyStale], pages whose words are already present, healthy, and
  /// cut by the session's dictionary are returned untouched — so repairing
  /// a book the OCR worker extended with IPADIC pages doesn't re-tokenize
  /// the pages that already match.
  static Future<List<MokuroPage>> segmentAllPages(
    List<MokuroPage> pages, {
    bool onlyStale = false,
  }) async {
    // Bring MeCab up before segmenting; without it we'd produce no words at
    // all. If init fails, return the pages
    // untouched so callers cache nothing new and the reader's self-heal
    // path retries on a later load. Segmentation only needs IPADIC; the
    // flag only decides anything in background isolates — on the main
    // isolate the startup warmup has already fixed the dictionary policy.
    final ready = await MecabService.instance.ensureInitialized(
      upgradeToEnhanced: false,
    );
    if (!ready) return pages;

    // Wait out any in-flight UniDic-lite upgrade so one run cannot mix
    // dictionaries mid-swap, then record which dictionary cut the word
    // boxes. Tap-time lookups tokenize with the live dictionary; the reader
    // re-segments pages whose recorded dictionary no longer matches it. In
    // background isolates (OCR worker) no upgrade ever starts, so this
    // resolves immediately with IPADIC.
    final layout = await MecabService.instance.settledLayout();

    final result = <MokuroPage>[];
    for (final page in pages) {
      if (page.blocks.isEmpty ||
          (onlyStale &&
              !pageNeedsWordSegmentation(page) &&
              !pageSegmentedWithDifferentDictionary(page, layout.label))) {
        result.add(page);
        continue;
      }
      final newBlocks = <MokuroTextBlock>[];
      for (int blockIdx = 0; blockIdx < page.blocks.length; blockIdx++) {
        final block = page.blocks[blockIdx];
        final words = _segmentBlock(block, blockIdx);
        newBlocks.add(block.copyWith(words: words));
      }
      result.add(
        page.copyWith(blocks: newBlocks, segmentationDictionary: layout.label),
      );
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

      // One MeCab parse for the whole line. An unusable parse collapses to
      // a single unannotated whole-line token — the broken-cache signature
      // blockHasBrokenWordSegmentation keys on, so self-heal retries it.
      final tokens = mecab.annotateTokens(lineText);
      if (tokens == null) continue;

      // Build words with bounding boxes; char offsets must match the
      // coordinates OCR tap targets use.
      int charPos = 0;
      for (final token in tokens) {
        final surface = token.surface;
        final charStart = charPos;
        final charEnd = charPos + surface.length;

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
              dictionaryForm: token.dictionaryForm,
              reading: token.reading,
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
