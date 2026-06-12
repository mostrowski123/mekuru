import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

void main() {
  // ── extractSentenceContext (static, no MeCab init needed) ──────────

  group('MecabService.extractSentenceContext', () {
    test('extracts sentence ending with 。', () {
      const text = '今日は天気がいい。明日は雨です。';
      // charOffset 1 → in first sentence
      final result = MecabService.extractSentenceContext(text, 1);
      expect(result, '今日は天気がいい。');
    });

    test('extracts sentence ending with ！', () {
      const text = 'すごい！楽しかった。';
      final result = MecabService.extractSentenceContext(text, 0);
      expect(result, 'すごい！');
    });

    test('extracts sentence ending with ？', () {
      const text = '何ですか？知りません。';
      final result = MecabService.extractSentenceContext(text, 2);
      expect(result, '何ですか？');
    });

    test('extracts second sentence from multi-sentence text', () {
      const text = '今日は天気がいい。明日は雨です。';
      // charOffset 9 → '明' in the second sentence
      final result = MecabService.extractSentenceContext(text, 9);
      expect(result, '明日は雨です。');
    });

    test('returns whole text when no delimiters present', () {
      const text = '天気がいい';
      final result = MecabService.extractSentenceContext(text, 2);
      expect(result, '天気がいい');
    });

    test('handles offset at start of text', () {
      const text = '今日は天気がいい。明日は雨です。';
      final result = MecabService.extractSentenceContext(text, 0);
      expect(result, '今日は天気がいい。');
    });

    test('handles offset at end of text', () {
      const text = '今日は天気がいい。明日は雨です。';
      final lastIndex = text.length - 1;
      final result = MecabService.extractSentenceContext(text, lastIndex);
      expect(result, '明日は雨です。');
    });

    test('handles empty text', () {
      final result = MecabService.extractSentenceContext('', 0);
      expect(result, '');
    });

    test('handles single character text', () {
      final result = MecabService.extractSentenceContext('あ', 0);
      expect(result, 'あ');
    });

    test('clamps offset to valid range', () {
      const text = '短い。';
      // Offset beyond text length should be clamped
      final result = MecabService.extractSentenceContext(text, 100);
      // Clamped to last char index (2), which is 。 — delimiter at offset, sentence is '短い。'
      expect(result, '短い。');
    });

    test('handles newline as delimiter', () {
      const text = '一行目\n二行目';
      final result = MecabService.extractSentenceContext(text, 0);
      // Scans forward from offset 0, finds \n at index 3
      expect(result, '一行目');
    });

    test('handles fullwidth exclamation mark ！', () {
      const text = 'やった！すごい！';
      final result = MecabService.extractSentenceContext(text, 0);
      expect(result, 'やった！');
    });

    test('handles fullwidth question mark ？', () {
      const text = '本当？嘘？';
      final result = MecabService.extractSentenceContext(text, 3);
      expect(result, '嘘？');
    });

    test('handles consecutive delimiters', () {
      const text = 'えっ？！本当？';
      // charOffset 0 → should find first delimiter
      final result = MecabService.extractSentenceContext(text, 0);
      expect(result, 'えっ？');
    });
  });

  // ── WordLookupResult ────────────────────────────────────────────────

  group('WordLookupResult', () {
    test('stores all fields correctly', () {
      const result = WordLookupResult(
        surfaceForm: '食べた',
        dictionaryForm: '食べる',
        reading: 'タベタ',
        sentenceContext: '昨日ケーキを食べた。',
        tokenStartOffset: 5,
      );

      expect(result.surfaceForm, '食べた');
      expect(result.dictionaryForm, '食べる');
      expect(result.reading, 'タベタ');
      expect(result.sentenceContext, '昨日ケーキを食べた。');
      expect(result.tokenStartOffset, 5);
    });
  });

  // ── identifyWord (requires MeCab init — skipped in unit tests) ─────
  // NOTE: MecabService.identifyWord requires the IPAdic assets to be
  // available, which is only the case on a device/emulator. These tests
  // verify the guard-clause behavior that does NOT require init.

  group('MecabService.identifyWord — guard clauses', () {
    // Use a fresh instance (not initialized) to test guard clauses.
    late MecabService service;

    setUp(() {
      // Access the singleton (it won't be initialized in test environment)
      service = MecabService.instance;
    });

    test('returns null when not initialized', () {
      // MecabService.instance._initialized is false in test environment
      // (no assets available), so identifyWord should return null.
      final result = service.identifyWord('食べる', 0);
      expect(result, isNull);
    });

    test('returns null for empty text', () {
      final result = service.identifyWord('', 0);
      expect(result, isNull);
    });

    test('returns null for negative offset', () {
      final result = service.identifyWord('食べる', -1);
      expect(result, isNull);
    });

    test('returns null for offset beyond text length', () {
      final result = service.identifyWord('食べる', 100);
      expect(result, isNull);
    });
  });

  // ── copyAssetsToDir (atomic, self-healing asset install) ───────────

  group('MecabService.copyAssetsToDir', () {
    late Directory destDir;

    setUp(() {
      destDir = Directory.systemTemp.createTempSync('mecab_copy_test_');
    });

    tearDown(() {
      if (destDir.existsSync()) {
        destDir.deleteSync(recursive: true);
      }
    });

    ByteData byteData(List<int> bytes) =>
        ByteData.view(Uint8List.fromList(bytes).buffer);

    File destFile(String name) => File('${destDir.path}/$name');

    test(
      'copies missing files with exact bytes and writes the marker',
      () async {
        final assets = {
          'assets/test/a.dic': [1, 2, 3],
          'assets/test/b.dic': [4, 5],
        };

        await MecabService.copyAssetsToDir(
          assetPrefix: 'assets/test',
          fileNames: ['a.dic', 'b.dic'],
          destDir: destDir,
          loadAsset: (key) async => byteData(assets[key]!),
        );

        expect(destFile('a.dic').readAsBytesSync(), [1, 2, 3]);
        expect(destFile('b.dic').readAsBytesSync(), [4, 5]);
        expect(destFile('.install_ok').existsSync(), isTrue);
      },
    );

    test('re-copies a truncated file when the marker is absent', () async {
      destFile('a.dic').writeAsBytesSync([1]); // truncated leftover

      await MecabService.copyAssetsToDir(
        assetPrefix: 'assets/test',
        fileNames: ['a.dic'],
        destDir: destDir,
        loadAsset: (key) async => byteData([1, 2, 3]),
      );

      expect(destFile('a.dic').readAsBytesSync(), [1, 2, 3]);
    });

    test('leaves a same-size file untouched (size-only heuristic)', () async {
      destFile('a.dic').writeAsBytesSync([9, 9, 9]);

      await MecabService.copyAssetsToDir(
        assetPrefix: 'assets/test',
        fileNames: ['a.dic'],
        destDir: destDir,
        loadAsset: (key) async => byteData([1, 2, 3]),
      );

      expect(destFile('a.dic').readAsBytesSync(), [9, 9, 9]);
    });

    test('skips asset loading entirely when marker and files exist', () async {
      destFile('a.dic').writeAsBytesSync([1]); // even a truncated file
      destFile('.install_ok').writeAsStringSync('');
      final loadedKeys = <String>[];

      await MecabService.copyAssetsToDir(
        assetPrefix: 'assets/test',
        fileNames: ['a.dic'],
        destDir: destDir,
        loadAsset: (key) async {
          loadedKeys.add(key);
          return byteData([1, 2, 3]);
        },
      );

      expect(loadedKeys, isEmpty);
    });

    test(
      'runs the full verify when marker exists but a file is missing',
      () async {
        destFile('.install_ok').writeAsStringSync('');

        await MecabService.copyAssetsToDir(
          assetPrefix: 'assets/test',
          fileNames: ['a.dic'],
          destDir: destDir,
          loadAsset: (key) async => byteData([1, 2, 3]),
        );

        expect(destFile('a.dic').readAsBytesSync(), [1, 2, 3]);
      },
    );

    test('cleans up orphaned .tmp files and leaves none behind', () async {
      destFile('stale.dic.tmp').writeAsBytesSync([0]);

      await MecabService.copyAssetsToDir(
        assetPrefix: 'assets/test',
        fileNames: ['a.dic'],
        destDir: destDir,
        loadAsset: (key) async => byteData([1, 2, 3]),
      );

      final tmpFiles = destDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.tmp'),
      );
      expect(tmpFiles, isEmpty);
    });

    test('propagates a loader failure mid-batch, keeps earlier files, '
        'writes no marker', () async {
      await expectLater(
        MecabService.copyAssetsToDir(
          assetPrefix: 'assets/test',
          fileNames: ['a.dic', 'b.dic'],
          destDir: destDir,
          loadAsset: (key) async {
            if (key.endsWith('b.dic')) throw Exception('asset missing');
            return byteData([1, 2, 3]);
          },
        ),
        throwsA(isA<Exception>()),
      );

      expect(destFile('a.dic').readAsBytesSync(), [1, 2, 3]);
      expect(destFile('.install_ok').existsSync(), isFalse);
    });
  });

  // ── init re-entrancy ────────────────────────────────────────────────
  // In the unit-test environment init() always fails (no path_provider
  // plugin), which is exactly what these tests need: they verify the
  // memoization and retry behavior, not a successful initialization.

  group('MecabService.init re-entrancy', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('concurrent calls share the same in-flight future', () async {
      final first = MecabService.instance.init();
      final second = MecabService.instance.init();

      expect(identical(first, second), isTrue);
      await expectLater(first, throwsA(anything));
    });

    test(
      'a failed init can be retried without LateInitializationError',
      () async {
        final first = MecabService.instance.init();
        await expectLater(first, throwsA(anything));

        final second = MecabService.instance.init();
        expect(identical(first, second), isFalse);
        // The retry must fail with the same environment error, not a
        // LateInitializationError from re-assigning internal state.
        await expectLater(second, throwsA(isA<Exception>()));
      },
    );
  });

  // ── WordLookupResult — tokenStartOffset ───────────────────────────

  group('WordLookupResult — tokenStartOffset', () {
    test('tokenStartOffset defaults correctly', () {
      const result = WordLookupResult(
        surfaceForm: '国立',
        dictionaryForm: '国立',
        reading: 'コクリツ',
        sentenceContext: '国立の学校',
        tokenStartOffset: 0,
      );
      expect(result.tokenStartOffset, 0);
    });

    test('tokenStartOffset reflects position in text', () {
      const result = WordLookupResult(
        surfaceForm: '学校',
        dictionaryForm: '学校',
        reading: 'ガッコウ',
        sentenceContext: '国立の学校',
        tokenStartOffset: 3,
      );
      expect(result.tokenStartOffset, 3);
      expect(result.surfaceForm.length, 2);
    });
  });
}
