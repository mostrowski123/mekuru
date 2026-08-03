import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/services/furigana_generator.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

/// Integration test for the furigana generation pipeline.
///
/// Unit tests cover [FuriganaGenerator] with a fake tokenizer, but cannot
/// verify that MeCab actually loads its bundled IPADIC dictionary and produces
/// usable per-kanji segments on a real device. This test exercises the full
/// path on the emulator: asset copy → MeCab init → tokenizeForFurigana →
/// FuriganaGenerator.generate.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await MecabService.instance.init();
  });

  group('FuriganaGenerator with real MeCab', () {
    late FuriganaGenerator generator;

    setUp(() {
      generator = const FuriganaGenerator(MecabFuriganaTokenizer());
    });

    test('emits per-kanji ruby segments for mixed kanji/kana sentence', () async {
      // Use a representative Japanese sentence with multiple kanji words.
      final results = (await generator.generate(const ['今日は晴れだ']))!;
      expect(results, hasLength(1));

      final segments = results.first['segments'] as List;
      expect(segments, isNotEmpty);

      // Concatenating all segment text must reproduce the input exactly.
      final reconstructed = segments
          .map((s) => (s as Map)['t'] as String)
          .join();
      expect(reconstructed, '今日は晴れだ');

      // At least one segment must carry furigana, and every furigana-bearing
      // segment must contain at least one kanji character.
      final withFurigana = segments
          .cast<Map>()
          .where((s) => s['f'] != null)
          .toList();
      expect(
        withFurigana,
        isNotEmpty,
        reason: 'expected at least one ruby segment for kanji in "今日は晴れだ"',
      );
      final kanjiRegex = RegExp(r'[㐀-䶿一-鿿々〆ヵヶ]');
      for (final seg in withFurigana) {
        expect(kanjiRegex.hasMatch(seg['t'] as String), isTrue);
        expect(seg['f'], isA<String>());
        expect((seg['f'] as String).isNotEmpty, isTrue);
      }
    });

    test('kana-only input emits no furigana', () async {
      final results = (await generator.generate(const ['ひらがなだけです']))!;
      final segments = results.first['segments'] as List;
      for (final seg in segments.cast<Map>()) {
        expect(seg['f'], isNull, reason: 'kana-only input should have no ruby');
      }
      final reconstructed = segments
          .map((s) => (s as Map)['t'] as String)
          .join();
      expect(reconstructed, 'ひらがなだけです');
    });

    test('processes a batch of varied inputs in order', () async {
      const inputs = ['食べた', '日本語', 'カタカナ', '走る'];
      final results = (await generator.generate(inputs))!;
      expect(results, hasLength(inputs.length));
      for (var i = 0; i < inputs.length; i++) {
        expect(results[i]['source'], inputs[i]);
        final segments = results[i]['segments'] as List;
        final reconstructed = segments
            .map((s) => (s as Map)['t'] as String)
            .join();
        expect(reconstructed, inputs[i]);
      }

      // The kanji-bearing entries must produce at least one ruby segment.
      for (final kanjiInput in const ['食べた', '日本語', '走る']) {
        final entry = results.firstWhere((r) => r['source'] == kanjiInput);
        final segments = entry['segments'] as List;
        final hasFurigana = segments.cast<Map>().any((s) => s['f'] != null);
        expect(
          hasFurigana,
          isTrue,
          reason: '"$kanjiInput" must produce at least one ruby segment',
        );
      }
    });

    test('gikun compounds use the bundled user-dictionary reading', () async {
      // IPADIC alone mistokenizes these compounds (二人 → に+にん, 今日 → こん+
      // にち, etc). The bundled user.dic supplies the correct gikun reading
      // and MeCab prefers it via the -u flag set up in MecabService.init().
      const expectations = <String, String>{
        '二人': 'ふたり',
        '一人': 'ひとり',
        '今日': 'きょう',
        '上手': 'じょうず',
        '田舎': 'いなか',
        '七夕': 'たなばた',
      };
      for (final entry in expectations.entries) {
        final word = entry.key;
        final reading = entry.value;
        final segments =
            (await generator.generate([word]))!.first['segments'] as List;
        expect(
          segments,
          hasLength(1),
          reason: '$word should be a single segment, got $segments',
        );
        final seg = segments.first as Map;
        expect(
          seg['t'],
          word,
          reason: '$word segment text should match the input',
        );
        expect(
          seg['f'],
          reading,
          reason: '$word should carry reading $reading, got $segments',
        );
      }
    });

    test('readings are hiragana, not katakana', () async {
      // MeCab's raw reading field is katakana; FuriganaGenerator must
      // convert it to hiragana before emitting the segment.
      final results = (await generator.generate(const ['食べた']))!;
      final segments = results.first['segments'] as List;
      final furiganaSegs = segments.cast<Map>().where((s) => s['f'] != null);
      expect(furiganaSegs, isNotEmpty);
      for (final seg in furiganaSegs) {
        final f = seg['f'] as String;
        for (final rune in f.runes) {
          // Reject katakana block U+30A1–U+30F6.
          expect(
            rune < 0x30A1 || rune > 0x30F6,
            isTrue,
            reason:
                'furigana "$f" contains katakana character U+'
                '${rune.toRadixString(16)}',
          );
        }
      }
    });
  });
}
