import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';

TocPlacement _entry(String title, int spine, [bool? anchorAfter = false]) =>
    (title: title, spine: spine, anchorAfter: anchorAfter);

void main() {
  // Depth first, as the bridge walks it: 第一部 > 第一章, 第二章; 第二部 >
  // 第三章. 第二章 spans spine items 4 and 5; only 4 is in the contents.
  final nested = [
    _entry('第一部', 1),
    _entry('第一章', 2),
    _entry('第二章', 4),
    _entry('第二部', 6),
    _entry('第三章', 7),
  ];

  test('names the chapter of the latest item not after the position', () {
    expect(pickChapterTitle(2, nested), '第一章');
    expect(pickChapterTitle(5, nested), '第二章');
    expect(pickChapterTitle(6, nested), '第二部');
    expect(pickChapterTitle(9, nested), '第三章');
    expect(pickChapterTitle(0, nested), '');
  });

  test('ignores entries listed out of reading order', () {
    expect(pickChapterTitle(5, [...nested, _entry('奥付', 1)]), '第二章');
  });

  test('skips entries without a title or a spine item', () {
    expect(pickChapterTitle(5, [_entry('第一章', 2), _entry('', 3)]), '第一章');
    expect(pickChapterTitle(5, [_entry('第一章', 2), _entry('付録', -1)]), '第一章');
  });

  group('several chapters in one file', () {
    test('takes the last anchor not after the position', () {
      final toc = [
        _entry('第一章', 3),
        _entry('第二章', 3, false),
        _entry('第三章', 3, true),
      ];
      expect(pickChapterTitle(3, toc), '第二章');
    });

    test('keeps the previous file when the first anchor comes later', () {
      final toc = [_entry('第一章', 2), _entry('第二章', 3, true)];
      expect(pickChapterTitle(3, toc), '第一章');
    });

    test('falls back to the first entry when anchors are unknown', () {
      final toc = [
        _entry('第一章', 2),
        _entry('第二章', 3, null),
        _entry('第三章', 3, null),
      ];
      expect(pickChapterTitle(3, toc), '第二章');
    });
  });
}
