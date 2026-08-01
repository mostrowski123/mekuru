import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/stats/data/services/page_char_counter.dart';

MokuroTextBlock block(List<String> lines) => MokuroTextBlock(
  box: const [0, 0, 10, 10],
  vertical: true,
  fontSize: 12,
  linesCoords: const [],
  lines: lines,
);

MokuroPage page(List<MokuroTextBlock> blocks) => MokuroPage(
  pageIndex: 0,
  imageFileName: 'page.jpg',
  imgWidth: 800,
  imgHeight: 1200,
  blocks: blocks,
);

void main() {
  test('sums characters across all blocks on the page', () {
    final result = charCountForPage(
      page([
        block(['こんにちは']),
        block(['世界', 'です']),
      ]),
    );

    expect(result, 9);
  });

  test('strips whitespace, newlines and full-width spaces', () {
    final result = charCountForPage(
      page([
        // 5 counted characters, then a whitespace-only line.
        block(['ねこ が\tいる', '  \n  ']),
        // 2 counted characters around an ideographic space.
        block(['は　い']),
      ]),
    );

    expect(result, 7);
  });

  test('page with no blocks counts zero', () {
    expect(charCountForPage(page([])), 0);
  });

  test('blocks with only empty lines count zero', () {
    expect(
      charCountForPage(
        page([
          block(const []),
          block(['', '   ']),
        ]),
      ),
      0,
    );
  });
}
