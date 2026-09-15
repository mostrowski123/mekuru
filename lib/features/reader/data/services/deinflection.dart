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

  // Breadth-first over the rule table, bounded by _maxDeinflectionDepth:
  // each pass unwinds one ending, so 食べていました → 食べています →
  // 食べている → 食べて → 食べる. Depth-1 candidates keep their rule order.
  final seen = <String>{surfaceForm};
  final detailed = <DeinflectedCandidate>[];
  var frontier = [surfaceForm];

  for (var depth = 0; depth < _maxDeinflectionDepth; depth++) {
    final next = <String>[];
    for (final form in frontier) {
      for (final candidate in _deinflectOnce(form)) {
        if (seen.add(candidate.term)) {
          detailed.add(candidate);
          next.add(candidate.term);
        }
      }
    }
    if (next.isEmpty) break;
    frontier = next;
  }

  return detailed;
}

/// One pass of every rule (and irregular alias) over [form].
Iterable<DeinflectedCandidate> _deinflectOnce(String form) sync* {
  for (final base in _irregularForms[form] ?? const <String>[]) {
    yield DeinflectedCandidate(term: base, family: DeinflectionFamily.verbal);
  }
  for (final rule in _deinflectionRules) {
    if (form.length > rule.suffix.length && form.endsWith(rule.suffix)) {
      final stem = form.substring(0, form.length - rule.suffix.length);
      for (final replacement in rule.replacements) {
        yield DeinflectedCandidate(
          term: stem + replacement,
          family: rule.family,
        );
      }
    }
  }
}

/// Passes of [_deinflectOnce] per lookup. Four covers the deepest common
/// stack (progressive + polite + past: ていました → ています → ている → て
/// → る) while keeping candidate sets small for the per-tap reader path.
const _maxDeinflectionDepth = 4;

/// Whole-word forms of the irregular verbs する and 来る, whose stems
/// change and so never reach the dictionary form through suffix rules.
/// Kanji 来 spellings do (来て → 来る via the て rule). Stacked endings still
/// chain through here: しませんでした → します → する.
const _irregularForms = <String, List<String>>{
  'した': ['する'],
  'します': ['する'],
  'して': ['する'],
  'しない': ['する'],
  'しよう': ['する'],
  'きた': ['来る', 'くる'],
  'きて': ['来る', 'くる'],
  'きます': ['来る', 'くる'],
  'こない': ['来る', 'くる'],
  'こよう': ['来る', 'くる'],
};

class _DeinflectionRule {
  final String suffix;
  final List<String> replacements;
  final DeinflectionFamily family;

  const _DeinflectionRule(this.suffix, this.replacements, this.family);
}

/// Conjugation reversal rules.
///
/// Rules are applied exhaustively (all matching rules contribute candidates)
/// and repeatedly (see [deinflectDetailed]), so a rule only needs to peel one
/// ending: stacked endings normalize to an intermediate form (ました → ます,
/// ている → て) that the basic rules then finish. Longer suffixes are listed
/// first for documentation clarity, but since all rules are checked
/// independently, ordering does not affect correctness.
const _deinflectionRules = [
  // ── Polite stacked endings → ます, which the ます rules then unwind ────
  _DeinflectionRule('ませんでした', ['ます'], DeinflectionFamily.verbal),
  _DeinflectionRule('ましょう', ['ます'], DeinflectionFamily.verbal),
  _DeinflectionRule('ました', ['ます'], DeinflectionFamily.verbal),
  _DeinflectionRule('ません', ['ます'], DeinflectionFamily.verbal),

  // ── Progressive (ている / てる) → te-form, which the て rules unwind ──
  // Its own た/ない/ます endings need no rules: 食べていた → 食べている via
  // the ichidan た rule, then here.
  _DeinflectionRule('ている', ['て'], DeinflectionFamily.verbal),
  _DeinflectionRule('でいる', ['で'], DeinflectionFamily.verbal),
  _DeinflectionRule('てる', ['て'], DeinflectionFamily.verbal),
  _DeinflectionRule('でる', ['で'], DeinflectionFamily.verbal),

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
