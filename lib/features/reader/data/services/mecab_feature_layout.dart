/// Maps MeCab feature columns to logical fields (dictionary form, reading).
///
/// IPADIC and UniDic place these fields at different column indexes and
/// encode loanwords differently, so callers pass the matching layout to
/// `MecabService.init`.
///
/// Pure Dart on purpose: Flutter-free logic (e.g. the mokuro segmentation
/// repair heuristics) compares dictionary labels without pulling in the
/// MeCab plugin.
class MecabFeatureLayout {
  final int _dictionaryFormIndex;
  final int _readingIndex;
  final bool _stripLoanwordGloss;

  /// Identifies the dictionary this layout belongs to.
  ///
  /// Persisted as `segmentationDictionary` in every manga's
  /// `pages_cache.json` (word-segmentation provenance). Renaming a label
  /// invalidates those caches in the field and re-segments every installed
  /// book — treat the values as an on-disk contract, not display text.
  final String label;

  const MecabFeatureLayout._({
    required int dictionaryFormIndex,
    required int readingIndex,
    required bool stripLoanwordGloss,
    required this.label,
  }) : _dictionaryFormIndex = dictionaryFormIndex,
       _readingIndex = readingIndex,
       _stripLoanwordGloss = stripLoanwordGloss;

  /// IPADIC: `features[6]` is the lemma (dictionary form) and `features[7]`
  /// is the surface reading in katakana.
  static const ipadic = MecabFeatureLayout._(
    dictionaryFormIndex: 6,
    readingIndex: 7,
    stripLoanwordGloss: false,
    label: 'IPADIC',
  );

  /// UniDic (unidic-lite 2.1.2): `features[7]` is the lemma and
  /// `features[17]` is the surface kana form without long-vowel `ー`
  /// marks. Loanword lemmas include an `-english_gloss` suffix that must
  /// be stripped to recover the dictionary key.
  static const unidicLite = MecabFeatureLayout._(
    dictionaryFormIndex: 7,
    readingIndex: 17,
    stripLoanwordGloss: true,
    label: 'UniDic',
  );

  /// Returns `null` when the column is missing, `*`, or strips to empty.
  String? dictionaryForm(List<String> features) {
    if (features.length <= _dictionaryFormIndex) return null;
    final raw = features[_dictionaryFormIndex];
    if (raw.isEmpty || raw == '*') return null;
    if (!_stripLoanwordGloss) return raw;
    final dashIdx = raw.indexOf('-');
    if (dashIdx < 0) return raw;
    final stripped = raw.substring(0, dashIdx);
    return stripped.isEmpty ? null : stripped;
  }

  /// Returns `''` when the column is missing or `*`.
  String reading(List<String> features) {
    if (features.length <= _readingIndex) return '';
    final raw = features[_readingIndex];
    return (raw.isEmpty || raw == '*') ? '' : raw;
  }
}
