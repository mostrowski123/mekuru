enum DeinflectionFamily { verbal, adjective }

class DeinflectedCandidate {
  final String term;
  final DeinflectionFamily family;

  const DeinflectedCandidate({required this.term, required this.family});
}

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
  return deinflectDetailed(
    surfaceForm,
  ).map((candidate) => candidate.term).toList();
}

List<DeinflectedCandidate> deinflectDetailed(String surfaceForm) {
  if (surfaceForm.length < 2) return [];

  final candidates = <String>{};
  final detailed = <DeinflectedCandidate>[];

  for (final rule in _deinflectionRules) {
    if (surfaceForm.length > rule.suffix.length &&
        surfaceForm.endsWith(rule.suffix)) {
      final stem = surfaceForm.substring(
        0,
        surfaceForm.length - rule.suffix.length,
      );
      for (final replacement in rule.replacements) {
        final candidate = stem + replacement;
        if (candidates.add(candidate)) {
          detailed.add(
            DeinflectedCandidate(term: candidate, family: rule.family),
          );
        }
      }
    }
  }

  return detailed;
}

class _DeinflectionRule {
  final String suffix;
  final List<String> replacements;
  final DeinflectionFamily family;

  const _DeinflectionRule(this.suffix, this.replacements, this.family);
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
  _DeinflectionRule('する', [''], DeinflectionFamily.verbal),
  //   駆使しない → 駆使する, 駆使 (negative)
  _DeinflectionRule('しない', ['する', ''], DeinflectionFamily.verbal),
  //   駆使される → 駆使する, 駆使 (passive)
  _DeinflectionRule('される', ['する', ''], DeinflectionFamily.verbal),
  //   駆使させる → 駆使する, 駆使 (causative)
  _DeinflectionRule('させる', ['する', ''], DeinflectionFamily.verbal),

  // ── Te-form (て / で) ────────────────────────────────────────────
  // Godan consonant-stem verbs:
  //   行く → 行って, 買う → 買って, 待つ → 待って, 走る → 走って (godan る)
  _DeinflectionRule('って', ['く', 'う', 'つ', 'る'], DeinflectionFamily.verbal),
  //   読む → 読んで, 飛ぶ → 飛んで, 死ぬ → 死んで
  _DeinflectionRule('んで', ['む', 'ぶ', 'ぬ'], DeinflectionFamily.verbal),
  //   書く → 書いて (most く-ending godan verbs)
  _DeinflectionRule('いて', ['く'], DeinflectionFamily.verbal),
  //   泳ぐ → 泳いで
  _DeinflectionRule('いで', ['ぐ'], DeinflectionFamily.verbal),
  //   話す → 話して, also する te-form: 駆使して → 駆使す, 駆使
  _DeinflectionRule('して', ['す', ''], DeinflectionFamily.verbal),
  // I-adjective te-form: 大きい → 大きくて
  _DeinflectionRule('くて', ['い'], DeinflectionFamily.adjective),
  // Ichidan verbs: 食べる → 食べて
  _DeinflectionRule('て', ['る'], DeinflectionFamily.verbal),

  // ── Ta-form (past tense た / だ) ─────────────────────────────────
  _DeinflectionRule('った', ['く', 'う', 'つ', 'る'], DeinflectionFamily.verbal),
  _DeinflectionRule('んだ', ['む', 'ぶ', 'ぬ'], DeinflectionFamily.verbal),
  _DeinflectionRule('いた', ['く'], DeinflectionFamily.verbal),
  _DeinflectionRule('いだ', ['ぐ'], DeinflectionFamily.verbal),
  //   話す → 話した, also する past: 駆使した → 駆使す, 駆使
  _DeinflectionRule('した', ['す', ''], DeinflectionFamily.verbal),
  // I-adjective past: 大きい → 大きかった
  _DeinflectionRule('かった', ['い'], DeinflectionFamily.adjective),
  // Ichidan verbs: 食べる → 食べた
  _DeinflectionRule('た', ['る'], DeinflectionFamily.verbal),

  // ── Negative (ない) ──────────────────────────────────────────────
  // Godan verbs: stem vowel changes to あ-row + ない
  _DeinflectionRule('かない', ['く'], DeinflectionFamily.verbal),
  _DeinflectionRule('がない', ['ぐ'], DeinflectionFamily.verbal),
  _DeinflectionRule('さない', ['す'], DeinflectionFamily.verbal),
  _DeinflectionRule('たない', ['つ'], DeinflectionFamily.verbal),
  _DeinflectionRule('なない', ['ぬ'], DeinflectionFamily.verbal),
  _DeinflectionRule('ばない', ['ぶ'], DeinflectionFamily.verbal),
  _DeinflectionRule('まない', ['む'], DeinflectionFamily.verbal),
  _DeinflectionRule('わない', ['う'], DeinflectionFamily.verbal),
  _DeinflectionRule('らない', ['る'], DeinflectionFamily.verbal),
  // I-adjective negative: 大きい → 大きくない
  _DeinflectionRule('くない', ['い'], DeinflectionFamily.adjective),
  // Ichidan verbs: 食べる → 食べない
  _DeinflectionRule('ない', ['る'], DeinflectionFamily.verbal),

  // ── Masu-form (ます) ─────────────────────────────────────────────
  _DeinflectionRule('きます', ['く'], DeinflectionFamily.verbal),
  _DeinflectionRule('ぎます', ['ぐ'], DeinflectionFamily.verbal),
  //   話す → 話します, also する polite: 駆使します → 駆使す, 駆使
  _DeinflectionRule('します', ['す', ''], DeinflectionFamily.verbal),
  _DeinflectionRule('ちます', ['つ'], DeinflectionFamily.verbal),
  _DeinflectionRule('にます', ['ぬ'], DeinflectionFamily.verbal),
  _DeinflectionRule('びます', ['ぶ'], DeinflectionFamily.verbal),
  _DeinflectionRule('みます', ['む'], DeinflectionFamily.verbal),
  _DeinflectionRule('います', ['う'], DeinflectionFamily.verbal),
  _DeinflectionRule('ります', ['る'], DeinflectionFamily.verbal),
  // Ichidan verbs: 食べる → 食べます
  _DeinflectionRule('ます', ['る'], DeinflectionFamily.verbal),
];
