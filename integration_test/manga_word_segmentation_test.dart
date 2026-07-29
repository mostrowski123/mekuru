// Runs MokuroWordSegmenter (one MeCab parse per line via annotateTokens) on
// representative Japanese lines with real MeCab and asserts every produced
// word matches the per-token identifyWordWithContext oracle — the
// pre-optimization code path: surfaces tile each line, and
// dictionaryForm/reading are null exactly where lookup rejects the token.
// The bracket-led line is the regression case: a naive one-call-at-offset-0
// refactor loses the whole line, because a leading 「 makes
// identifyWordWithContext return null.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_segmentation_repair.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

const _lines = <String>[
  '「こんにちは、世界」', // bracket-led: leading token is lookup-rejected
  '私は学校に行きました', // plain conjugated sentence
  'コーヒーを飲みたい', // katakana loanword
  'その本は面白かった!', // trailing punctuation
];

/// A vertical line quad `[topLeft, topRight, bottomRight, bottomLeft]` in
/// image-pixel coordinates, offset per line so quads don't overlap.
List<List<double>> _quadForLine(int lineIdx) {
  final x = 100.0 + lineIdx * 50;
  return [
    [x, 100],
    [x + 40, 100],
    [x + 40, 500],
    [x, 500],
  ];
}

MokuroPage _buildPage() {
  final block = MokuroTextBlock(
    box: [100, 100, 400, 500],
    vertical: true,
    fontSize: 24,
    linesCoords: [for (var i = 0; i < _lines.length; i++) _quadForLine(i)],
    lines: _lines,
  );
  return MokuroPage(
    pageIndex: 0,
    imageFileName: 'page_0.jpg',
    imgWidth: 800,
    imgHeight: 1200,
    blocks: [block],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    await MecabService.instance.resetForTest();
  });

  test(
    'segmenter output matches the per-token identifyWordWithContext oracle',
    () async {
      final pages = await MokuroWordSegmenter.segmentAllPages([_buildPage()]);
      final mecab = MecabService.instance;
      expect(
        mecab.isInitialized,
        isTrue,
        reason: 'segmentAllPages must bring MeCab up on device',
      );

      final block = pages.single.blocks.single;
      expect(block.words, isNotEmpty);
      expect(
        pages.single.segmentationDictionary,
        (await mecab.settledLayout()).label,
      );

      for (var lineIdx = 0; lineIdx < _lines.length; lineIdx++) {
        final lineText = _lines[lineIdx];
        final lineWords = block.words
            .where((w) => w.lineIndex == lineIdx)
            .toList();
        expect(lineWords, isNotEmpty, reason: 'no words for "$lineText"');

        // Tiling: surfaces reassemble the line and the char ranges are the
        // cumulative offsets bounding boxes are derived from.
        expect(lineWords.map((w) => w.surface).join(), lineText);
        var charPos = 0;
        for (final word in lineWords) {
          expect(word.charStartInLine, charPos);
          expect(word.charEndInLine, charPos + word.surface.length);
          charPos = word.charEndInLine;
        }

        // Oracle: the old code path asked identifyWordWithContext for every
        // token offset; the one-parse path must reproduce its annotations.
        for (final word in lineWords) {
          final oracle = mecab.identifyWordWithContext(
            lineText,
            word.charStartInLine,
          );
          if (oracle == null) {
            expect(
              word.dictionaryForm,
              isNull,
              reason: 'lookup rejects "${word.surface}" in "$lineText"',
            );
            expect(word.reading, isNull);
          } else {
            expect(word.surface, oracle.result.surfaceForm);
            expect(word.dictionaryForm, oracle.result.dictionaryForm);
            expect(word.reading, oracle.result.reading);
          }
        }
      }

      // The regression case: the bracket-led line keeps annotations on its
      // real words even though offset 0 is a rejected token.
      final bracketLine = block.words.where((w) => w.lineIndex == 0).toList();
      final openBracket = bracketLine.first;
      expect(openBracket.surface, '「');
      expect(openBracket.dictionaryForm, isNull);
      expect(openBracket.reading, isNull);
      final sekai = bracketLine.where((w) => w.surface == '世界').toList();
      expect(sekai, hasLength(1));
      expect(sekai.single.dictionaryForm, '世界');

      // Healthy output must not look like the broken-cache signature.
      expect(blockHasBrokenWordSegmentation(block), isFalse);
    },
  );

  test(
    'segmentAllPagesInBackground matches the direct on-isolate path',
    () async {
      final page = _buildPage();
      final direct = await MokuroWordSegmenter.segmentAllPages([page]);
      final background = await MokuroWordSegmenter.segmentAllPagesInBackground([
        page,
      ]);

      // Guard against trivially passing on two empty results.
      expect(background.single.blocks.single.words, isNotEmpty);
      expect(
        background.map((p) => p.toJson()).toList(),
        direct.map((p) => p.toJson()).toList(),
        reason:
            'the background isolate must attach to the same dictionary and '
            'produce identical words and provenance',
      );
    },
  );
}
