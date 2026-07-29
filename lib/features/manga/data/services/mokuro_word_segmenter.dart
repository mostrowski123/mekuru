import 'dart:convert';

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
  /// Runs every MeCab parse synchronously on the calling isolate — from the
  /// UI isolate use [segmentBookInBackground] instead.
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
      if (_pageUntouchedBySegmentation(
        page,
        onlyStale: onlyStale,
        dictionary: layout.label,
      )) {
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

  /// Like [segmentAllPages], but for a whole [MokuroBook]: runs the MeCab
  /// parses on a short-lived background isolate via
  /// [MecabService.runOffIsolate], and encodes the book's `pages_cache.json`
  /// content there too.
  ///
  /// [segmentAllPages]' page loop never awaits, so on the UI isolate a large
  /// book — an import, or a first-open self-heal of a legacy cache — becomes
  /// one unbroken chunk of FFI parses: a visible hang. Encoding the cache
  /// JSON afterwards is the same kind of hazard (a multi-MB string build for
  /// a long volume), so the worker does that too and returns both results.
  /// UI-isolate callers use this variant; code already off the UI isolate
  /// (the OCR worker) calls [segmentAllPages] directly rather than paying an
  /// isolate spawn per page.
  ///
  /// Existing words on pages this run re-segments are replaced wholesale, so
  /// they are stripped before the send to shrink the outbound copy. When
  /// MeCab is unavailable (init failed here, or the attach failed in the
  /// worker) nothing is segmented: the returned book is [book] itself —
  /// words intact, never the stripped copy — and `cacheJson` is null so
  /// callers neither pay an encode nor persist anything when nothing
  /// changed.
  static Future<({MokuroBook book, String? cacheJson})> segmentBookInBackground(
    MokuroBook book, {
    bool onlyStale = false,
  }) async {
    final mecab = MecabService.instance;
    if (!await mecab.ensureInitialized(upgradeToEnhanced: false)) {
      return (book: book, cacheJson: null);
    }
    // The same settled label runOffIsolate is about to capture for the
    // worker — the dictionary policy is fixed once settled — so strip
    // decisions here match segmentation decisions there.
    final dictionary = (await mecab.settledLayout()).label;
    final outbound = _stripReplacedWords(
      book,
      onlyStale: onlyStale,
      dictionary: dictionary,
    );
    final result = await mecab.runOffIsolate(
      () => _segmentAndEncode(outbound, onlyStale),
    );
    return result ?? (book: book, cacheJson: null);
  }

  /// Worker-isolate side of [segmentBookInBackground]: segment [book]'s
  /// pages and encode the result. Null when MeCab is not up on this isolate
  /// (the attach failed) — the caller then falls back to its original,
  /// un-stripped book.
  static Future<({MokuroBook book, String? cacheJson})?> _segmentAndEncode(
    MokuroBook book,
    bool onlyStale,
  ) async {
    if (!MecabService.instance.isInitialized) return null;
    final segmented = book.copyWith(
      pages: await segmentAllPages(book.pages, onlyStale: onlyStale),
    );
    return (book: segmented, cacheJson: jsonEncode(segmented.toJson()));
  }

  /// [book] with words removed from every page [segmentAllPages] will
  /// re-segment with these arguments. Pages the run leaves untouched keep
  /// their words, and pages with no words to drop keep their identity — so
  /// an import (no words yet) sends [book] through unchanged.
  static MokuroBook _stripReplacedWords(
    MokuroBook book, {
    required bool onlyStale,
    required String dictionary,
  }) {
    var stripped = false;
    final pages = book.pages.map((page) {
      if (_pageUntouchedBySegmentation(
            page,
            onlyStale: onlyStale,
            dictionary: dictionary,
          ) ||
          page.blocks.every((block) => block.words.isEmpty)) {
        return page;
      }
      stripped = true;
      return page.copyWith(
        blocks: [
          for (final block in page.blocks)
            block.words.isEmpty ? block : block.copyWith(words: const []),
        ],
      );
    }).toList();
    return stripped ? book.copyWith(pages: pages) : book;
  }

  /// Whether [segmentAllPages] with these arguments returns [page]
  /// untouched. Shared with [_stripReplacedWords] so the pre-send word strip
  /// can never disagree with the segmentation run about which pages get
  /// their words rebuilt.
  static bool _pageUntouchedBySegmentation(
    MokuroPage page, {
    required bool onlyStale,
    required String dictionary,
  }) =>
      page.blocks.isEmpty ||
      (onlyStale &&
          !pageNeedsWordSegmentation(page) &&
          !pageSegmentedWithDifferentDictionary(page, dictionary));

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
