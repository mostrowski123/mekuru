import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_segmentation_repair.dart';
import 'package:mekuru/features/reader/data/services/mecab_feature_layout.dart';

MokuroWord _word(
  String surface, {
  String? dictForm,
  String? reading,
  int lineIndex = 0,
  int charStart = 0,
}) {
  return MokuroWord(
    surface: surface,
    dictionaryForm: dictForm,
    reading: reading,
    boundingBox: const Rect.fromLTRB(0, 0, 10, 10),
    blockIndex: 0,
    lineIndex: lineIndex,
    charStartInLine: charStart,
    charEndInLine: charStart + surface.length,
  );
}

MokuroTextBlock _block(List<String> lines, List<MokuroWord> words) {
  return MokuroTextBlock(
    box: const [0, 0, 100, 100],
    vertical: true,
    fontSize: 16,
    linesCoords: [
      for (final _ in lines)
        [
          [0.0, 0.0],
          [100.0, 0.0],
          [100.0, 100.0],
          [0.0, 100.0],
        ],
    ],
    lines: lines,
    words: words,
  );
}

MokuroPage _page(
  List<MokuroTextBlock> blocks, {
  String? segmentationDictionary,
}) {
  return MokuroPage(
    pageIndex: 0,
    imageFileName: 'p1.jpg',
    imgWidth: 800,
    imgHeight: 1200,
    blocks: blocks,
    segmentationDictionary: segmentationDictionary,
  );
}

MokuroTextBlock _healthyBlock() =>
    _block(['はい'], [_word('はい', dictForm: 'はい', reading: 'ハイ')]);

void main() {
  group('blockHasBrokenWordSegmentation', () {
    test('detects the uninitialized-MeCab fallback signature', () {
      // tokenize() fell back to the whole line as one token, and
      // identifyWordWithContext() returned null → no dict form, no reading.
      final block = _block(['そんなことないよ'], [_word('そんなことないよ')]);
      expect(blockHasBrokenWordSegmentation(block), isTrue);
    });

    test('detects a broken word among healthy ones', () {
      // MeCab initialized midway through a segmentation run.
      final block = _block(
        ['そんなことないよ', 'はい'],
        [
          _word('そんなことないよ'),
          _word('はい', dictForm: 'はい', reading: 'ハイ', lineIndex: 1),
        ],
      );
      expect(blockHasBrokenWordSegmentation(block), isTrue);
    });

    test('accepts a healthy single-token line', () {
      // Real segmentation always sets a dictionary form when it produces a
      // word, even when a short line is genuinely a single token.
      final block = _block(
        ['はい'],
        [_word('はい', dictForm: 'はい', reading: 'ハイ')],
      );
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('accepts a word with only a reading', () {
      final block = _block(['はい'], [_word('はい', reading: 'ハイ')]);
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('accepts healthy multi-word segmentation', () {
      final block = _block(
        ['そんなことないよ'],
        [
          _word('そんな', dictForm: 'そんな'),
          _word('こと', dictForm: 'こと', charStart: 3),
          _word('ない', dictForm: 'ない', charStart: 5),
          _word('よ', dictForm: 'よ', charStart: 7),
        ],
      );
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('ignores a line-spanning word without Japanese content', () {
      // Punctuation-only lines can legitimately survive as one word with no
      // dictionary form; re-segmenting them would loop forever.
      final block = _block(['…!?'], [_word('…!?')]);
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('ignores words that do not span their whole line', () {
      final block = _block(['そんなことないよ'], [_word('そんな')]);
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('ignores words whose lineIndex is out of range', () {
      final block = _block(['そんなことないよ'], [_word('そんなことないよ', lineIndex: 3)]);
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });

    test('ignores a block with no words', () {
      final block = _block(['そんなことないよ'], const []);
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    });
  });

  group('pageNeedsWordSegmentation', () {
    test('true for a block with lines but no words', () {
      final page = _page([
        _block(['そんなことないよ'], const []),
      ]);
      expect(pageNeedsWordSegmentation(page), isTrue);
    });

    test('false for a healthy page', () {
      final page = _page([
        _block(['はい'], [_word('はい', dictForm: 'はい', reading: 'ハイ')]),
      ]);
      expect(pageNeedsWordSegmentation(page), isFalse);
    });

    test('false for a page without text blocks', () {
      expect(pageNeedsWordSegmentation(_page(const [])), isFalse);
    });
  });

  group('pageSegmentedWithDifferentDictionary', () {
    test('layout labels are an on-disk contract', () {
      // Persisted as segmentationDictionary in pages_cache.json; renaming a
      // label would re-segment every installed book on next open.
      expect(MecabFeatureLayout.ipadic.label, 'IPADIC');
      expect(MecabFeatureLayout.unidicLite.label, 'UniDic');
    });

    test('treats an unlabeled segmented page as IPADIC', () {
      final page = _page([_healthyBlock()]);
      expect(pageSegmentedWithDifferentDictionary(page, 'UniDic'), isTrue);
      expect(pageSegmentedWithDifferentDictionary(page, 'IPADIC'), isFalse);
    });

    test('compares the recorded label against the target dictionary', () {
      final page = _page([_healthyBlock()], segmentationDictionary: 'UniDic');
      expect(pageSegmentedWithDifferentDictionary(page, 'UniDic'), isFalse);
      expect(pageSegmentedWithDifferentDictionary(page, 'IPADIC'), isTrue);
    });

    test('ignores pages without any words regardless of label', () {
      final unsegmented = _page([
        _block(['そんなことないよ'], const []),
      ]);
      final empty = _page(const [], segmentationDictionary: 'UniDic');
      expect(
        pageSegmentedWithDifferentDictionary(unsegmented, 'UniDic'),
        isFalse,
      );
      expect(pageSegmentedWithDifferentDictionary(empty, 'IPADIC'), isFalse);
    });
  });

  group('pagesSegmentedWithDifferentDictionary', () {
    test('detects a single mismatched page among healthy ones', () {
      final pages = [
        _page([_healthyBlock()], segmentationDictionary: 'UniDic'),
        _page([_healthyBlock()]), // legacy IPADIC page, e.g. from OCR worker
      ];
      expect(pagesSegmentedWithDifferentDictionary(pages, 'UniDic'), isTrue);
    });

    test('false when every segmented page matches', () {
      final pages = [
        _page([_healthyBlock()], segmentationDictionary: 'UniDic'),
        _page(const []),
      ];
      expect(pagesSegmentedWithDifferentDictionary(pages, 'UniDic'), isFalse);
    });

    test('label survives a JSON round-trip', () {
      final page = _page([_healthyBlock()], segmentationDictionary: 'UniDic');
      final roundTripped = MokuroPage.fromJson(
        jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
      );
      expect(roundTripped.segmentationDictionary, 'UniDic');
      expect(
        pageSegmentedWithDifferentDictionary(roundTripped, 'IPADIC'),
        isTrue,
      );
    });
  });

  group('pagesNeedWordSegmentation', () {
    test('detects a broken cache after a JSON round-trip', () {
      // The fallback words are written to pages_cache.json; the null
      // dictForm/reading markers must survive serialization for the repair
      // to trigger on the next load.
      final broken = _page([
        _block(['そんなことないよ'], [_word('そんなことないよ')]),
      ]);
      final roundTripped = MokuroPage.fromJson(
        jsonDecode(jsonEncode(broken.toJson())) as Map<String, dynamic>,
      );
      expect(pagesNeedWordSegmentation([roundTripped]), isTrue);
    });
  });
}
