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
