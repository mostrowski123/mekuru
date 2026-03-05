import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';

void main() {
  // ── Te-form ──────────────────────────────────────────────────────

  group('deinflect — te-form', () {
    test('って produces く, う, つ, る candidates', () {
      final results = deinflect('行って');
      expect(results, containsAll(['行く', '行う', '行つ', '行る']));
    });

    test('んで produces む, ぶ, ぬ candidates', () {
      final results = deinflect('読んで');
      expect(results, containsAll(['読む', '読ぶ', '読ぬ']));
    });

    test('いて produces く candidate', () {
      final results = deinflect('書いて');
      expect(results, contains('書く'));
    });

    test('いで produces ぐ candidate', () {
      final results = deinflect('泳いで');
      expect(results, contains('泳ぐ'));
    });

    test('して produces す candidate', () {
      final results = deinflect('話して');
      expect(results, contains('話す'));
    });

    test('くて produces い candidate (i-adjective)', () {
      final results = deinflect('大きくて');
      expect(results, contains('大きい'));
    });

    test('て produces る candidate (ichidan)', () {
      final results = deinflect('食べて');
      expect(results, contains('食べる'));
    });
  });

  // ── Ta-form (past) ──────────────────────────────────────────────

  group('deinflect — ta-form', () {
    test('った produces く, う, つ, る candidates', () {
      final results = deinflect('行った');
      expect(results, containsAll(['行く', '行う', '行つ', '行る']));
    });

    test('んだ produces む, ぶ, ぬ candidates', () {
      final results = deinflect('読んだ');
      expect(results, containsAll(['読む', '読ぶ', '読ぬ']));
    });

    test('いた produces く candidate', () {
      final results = deinflect('書いた');
      expect(results, contains('書く'));
    });

    test('いだ produces ぐ candidate', () {
      final results = deinflect('泳いだ');
      expect(results, contains('泳ぐ'));
    });

    test('した produces す candidate', () {
      final results = deinflect('話した');
      expect(results, contains('話す'));
    });

    test('かった produces い candidate (i-adjective past)', () {
      final results = deinflect('大きかった');
      expect(results, contains('大きい'));
    });

    test('た produces る candidate (ichidan past)', () {
      final results = deinflect('食べた');
      expect(results, contains('食べる'));
    });
  });

  // ── Negative (ない) ─────────────────────────────────────────────

  group('deinflect — negative', () {
    test('かない produces く candidate', () {
      final results = deinflect('行かない');
      expect(results, contains('行く'));
    });

    test('がない produces ぐ candidate', () {
      final results = deinflect('泳がない');
      expect(results, contains('泳ぐ'));
    });

    test('さない produces す candidate', () {
      final results = deinflect('話さない');
      expect(results, contains('話す'));
    });

    test('まない produces む candidate', () {
      final results = deinflect('読まない');
      expect(results, contains('読む'));
    });

    test('わない produces う candidate', () {
      final results = deinflect('買わない');
      expect(results, contains('買う'));
    });

    test('ばない produces ぶ candidate', () {
      final results = deinflect('飛ばない');
      expect(results, contains('飛ぶ'));
    });

    test('らない produces る candidate (godan る)', () {
      final results = deinflect('走らない');
      expect(results, contains('走る'));
    });

    test('くない produces い candidate (i-adjective negative)', () {
      final results = deinflect('大きくない');
      expect(results, contains('大きい'));
    });

    test('ない produces る candidate (ichidan negative)', () {
      final results = deinflect('食べない');
      expect(results, contains('食べる'));
    });
  });

  // ── Masu-form ───────────────────────────────────────────────────

  group('deinflect — masu-form', () {
    test('きます produces く candidate', () {
      final results = deinflect('行きます');
      expect(results, contains('行く'));
    });

    test('ぎます produces ぐ candidate', () {
      final results = deinflect('泳ぎます');
      expect(results, contains('泳ぐ'));
    });

    test('します produces す candidate', () {
      final results = deinflect('話します');
      expect(results, contains('話す'));
    });

    test('みます produces む candidate', () {
      final results = deinflect('読みます');
      expect(results, contains('読む'));
    });

    test('います produces う candidate', () {
      final results = deinflect('買います');
      expect(results, contains('買う'));
    });

    test('ります produces る candidate', () {
      final results = deinflect('走ります');
      expect(results, contains('走る'));
    });

    test('ます produces る candidate (ichidan)', () {
      final results = deinflect('食べます');
      expect(results, contains('食べる'));
    });
  });

  // ── する verbs (サ変) ──────────────────────────────────────────

  group('deinflect — する verbs', () {
    test('する produces noun stem (駆使する → 駆使)', () {
      final results = deinflect('駆使する');
      expect(results, contains('駆使'));
    });

    test('する produces noun stem for kana input (くしする → くし)', () {
      final results = deinflect('くしする');
      expect(results, contains('くし'));
    });

    test('した produces noun stem (駆使した → 駆使)', () {
      final results = deinflect('駆使した');
      expect(results, contains('駆使'));
    });

    test('した still produces す candidate for godan verbs (話した → 話す)', () {
      final results = deinflect('話した');
      expect(results, contains('話す'));
    });

    test('して produces noun stem (駆使して → 駆使)', () {
      final results = deinflect('駆使して');
      expect(results, contains('駆使'));
    });

    test('して still produces す candidate for godan verbs (話して → 話す)', () {
      final results = deinflect('話して');
      expect(results, contains('話す'));
    });

    test('します produces noun stem (駆使します → 駆使)', () {
      final results = deinflect('駆使します');
      expect(results, contains('駆使'));
    });

    test('します still produces す candidate for godan verbs (話します → 話す)', () {
      final results = deinflect('話します');
      expect(results, contains('話す'));
    });

    test('しない produces noun stem and する form (駆使しない → 駆使, 駆使する)', () {
      final results = deinflect('駆使しない');
      expect(results, contains('駆使'));
      expect(results, contains('駆使する'));
    });

    test('される produces noun stem and する form (駆使される → 駆使, 駆使する)', () {
      final results = deinflect('駆使される');
      expect(results, contains('駆使'));
      expect(results, contains('駆使する'));
    });

    test('させる produces noun stem and する form (駆使させる → 駆使, 駆使する)', () {
      final results = deinflect('駆使させる');
      expect(results, contains('駆使'));
      expect(results, contains('駆使する'));
    });
  });

  // ── Edge cases ──────────────────────────────────────────────────

  group('deinflect — edge cases', () {
    test('returns empty for single character', () {
      expect(deinflect('て'), isEmpty);
    });

    test('returns empty for empty string', () {
      expect(deinflect(''), isEmpty);
    });

    test('returns no duplicates', () {
      final results = deinflect('行って');
      expect(results.length, results.toSet().length);
    });

    test('suffix-only input produces candidates with tiny stems', () {
      // "って" matches the shorter "て" rule (stem="っ", candidate="っる")
      // but not the "って" rule (would need stem to be non-empty).
      // These won't match real dictionary entries but are harmless.
      final results = deinflect('って');
      expect(results, isNotEmpty);
    });

    test('dictionary form input with no matching suffix returns empty', () {
      // 行く is already a dictionary form; no suffix matches
      expect(deinflect('行く'), isEmpty);
    });

    test('行って generates both 行く and 行う (the core ambiguity)', () {
      final results = deinflect('行って');
      expect(results, contains('行く'));
      expect(results, contains('行う'));
    });
  });
}
