import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/zip_folder_name.dart';

/// Titles become folder names a person sees after unzipping on any desktop,
/// so they must survive Windows, macOS and Linux path rules unchanged.
void main() {
  String name(String title) =>
      zipFolderName(title, fallback: 'book_1_abcdef12');

  test('keeps ordinary Japanese and Latin titles as they are', () {
    expect(name('走れメロス'), '走れメロス');
    expect(name('Norwegian Wood'), 'Norwegian Wood');
  });

  test('replaces characters no desktop accepts and collapses whitespace', () {
    expect(name('漫画: 第1巻 / 上*?"<>|'), '漫画 第1巻 上');
    expect(name('a\tb\nc\x00d'), 'a b c d');
  });

  test('trims dots and spaces at both ends', () {
    expect(name('  .hidden. '), 'hidden');
    expect(name('Title...'), 'Title');
  });

  test('prefixes Windows reserved device names', () {
    expect(name('CON'), '_CON');
    expect(name('com1'), '_com1');
    expect(name('Console'), 'Console');
  });

  test('caps the length in characters and in UTF-8 bytes', () {
    final capped = name(List.filled(100, 'あ').join());
    expect(capped.runes.length, lessThanOrEqualTo(60));
    expect(utf8.encode(capped).length, lessThanOrEqualTo(150));
    expect(capped, List.filled(50, 'あ').join());
    expect(name('x' * 200).length, 60);
  });

  test('falls back to the directory name when nothing usable is left', () {
    expect(name(''), 'book_1_abcdef12');
    expect(name(' ... '), 'book_1_abcdef12');
    expect(name('???'), 'book_1_abcdef12');
  });

  group('dedupeFolderNames', () {
    test('suffixes later duplicates, case-insensitively', () {
      expect(dedupeFolderNames(['A', 'a', 'B', 'A']), [
        'A',
        'a (2)',
        'B',
        'A (3)',
      ]);
    });

    test('never collides with a name that appears later', () {
      expect(dedupeFolderNames(['A', 'A', 'A (2)']), ['A', 'A (3)', 'A (2)']);
    });

    test('leaves unique names untouched', () {
      expect(dedupeFolderNames(['走れメロス', '漫画']), ['走れメロス', '漫画']);
    });
  });
}
