/// Generates candidate dictionary forms by reversing common Japanese
/// verb and adjective conjugation patterns.
///
/// When MeCab chooses the wrong base form for an ambiguous surface form
/// (e.g., 行って parsed as 行う instead of 行く), this utility produces
/// all plausible dictionary forms so the lookup can find both readings.
///
/// Invalid candidates (e.g., 行つ from 行って) are expected to simply
/// not match in the dictionary and are harmless.
List<String> deinflect(String surfaceForm) {
  if (surfaceForm.length < 2) return [];

  final candidates = <String>{};

  for (final rule in _deinflectionRules) {
    if (surfaceForm.length > rule.suffix.length &&
        surfaceForm.endsWith(rule.suffix)) {
      final stem = surfaceForm.substring(
        0,
        surfaceForm.length - rule.suffix.length,
      );
      for (final replacement in rule.replacements) {
        candidates.add(stem + replacement);
      }
    }
  }

  return candidates.toList();
}

class _DeinflectionRule {
  final String suffix;
  final List<String> replacements;
  const _DeinflectionRule(this.suffix, this.replacements);
}

/// Conjugation reversal rules.
///
/// Rules are applied exhaustively (all matching rules contribute candidates).
/// Longer suffixes are listed first for documentation clarity, but since all
/// rules are checked independently, ordering does not affect correctness.
const _deinflectionRules = [
  // ── する verbs (サ変) ────────────────────────────────────────────
  // Dictionary entries often store the noun stem only (e.g., 駆使),
  // but MeCab may return the する-verb form (e.g., 駆使する).
  // These rules strip する and its conjugations to produce the noun stem.
  //   駆使する → 駆使 (dictionary form)
  _DeinflectionRule('する', ['']),
  //   駆使しない → 駆使する, 駆使 (negative)
  _DeinflectionRule('しない', ['する', '']),
  //   駆使される → 駆使する, 駆使 (passive)
  _DeinflectionRule('される', ['する', '']),
  //   駆使させる → 駆使する, 駆使 (causative)
  _DeinflectionRule('させる', ['する', '']),

  // ── Te-form (て / で) ────────────────────────────────────────────
  // Godan consonant-stem verbs:
  //   行く → 行って, 買う → 買って, 待つ → 待って, 走る → 走って (godan る)
  _DeinflectionRule('って', ['く', 'う', 'つ', 'る']),
  //   読む → 読んで, 飛ぶ → 飛んで, 死ぬ → 死んで
  _DeinflectionRule('んで', ['む', 'ぶ', 'ぬ']),
  //   書く → 書いて (most く-ending godan verbs)
  _DeinflectionRule('いて', ['く']),
  //   泳ぐ → 泳いで
  _DeinflectionRule('いで', ['ぐ']),
  //   話す → 話して, also する te-form: 駆使して → 駆使す, 駆使
  _DeinflectionRule('して', ['す', '']),
  // I-adjective te-form: 大きい → 大きくて
  _DeinflectionRule('くて', ['い']),
  // Ichidan verbs: 食べる → 食べて
  _DeinflectionRule('て', ['る']),

  // ── Ta-form (past tense た / だ) ─────────────────────────────────
  _DeinflectionRule('った', ['く', 'う', 'つ', 'る']),
  _DeinflectionRule('んだ', ['む', 'ぶ', 'ぬ']),
  _DeinflectionRule('いた', ['く']),
  _DeinflectionRule('いだ', ['ぐ']),
  //   話す → 話した, also する past: 駆使した → 駆使す, 駆使
  _DeinflectionRule('した', ['す', '']),
  // I-adjective past: 大きい → 大きかった
  _DeinflectionRule('かった', ['い']),
  // Ichidan verbs: 食べる → 食べた
  _DeinflectionRule('た', ['る']),

  // ── Negative (ない) ──────────────────────────────────────────────
  // Godan verbs: stem vowel changes to あ-row + ない
  _DeinflectionRule('かない', ['く']),
  _DeinflectionRule('がない', ['ぐ']),
  _DeinflectionRule('さない', ['す']),
  _DeinflectionRule('たない', ['つ']),
  _DeinflectionRule('なない', ['ぬ']),
  _DeinflectionRule('ばない', ['ぶ']),
  _DeinflectionRule('まない', ['む']),
  _DeinflectionRule('わない', ['う']),
  _DeinflectionRule('らない', ['る']),
  // I-adjective negative: 大きい → 大きくない
  _DeinflectionRule('くない', ['い']),
  // Ichidan verbs: 食べる → 食べない
  _DeinflectionRule('ない', ['る']),

  // ── Masu-form (ます) ─────────────────────────────────────────────
  _DeinflectionRule('きます', ['く']),
  _DeinflectionRule('ぎます', ['ぐ']),
  //   話す → 話します, also する polite: 駆使します → 駆使す, 駆使
  _DeinflectionRule('します', ['す', '']),
  _DeinflectionRule('ちます', ['つ']),
  _DeinflectionRule('にます', ['ぬ']),
  _DeinflectionRule('びます', ['ぶ']),
  _DeinflectionRule('みます', ['む']),
  _DeinflectionRule('います', ['う']),
  _DeinflectionRule('ります', ['る']),
  // Ichidan verbs: 食べる → 食べます
  _DeinflectionRule('ます', ['る']),
];
