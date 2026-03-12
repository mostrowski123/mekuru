import 'package:mekuru/core/database/database_provider.dart';

class ResolvedPartOfSpeech {
  final String label;
  final String? localizationKey;

  const ResolvedPartOfSpeech({required this.label, this.localizationKey});
}

/// Resolves friendly part-of-speech labels from raw Yomitan entry tags.
abstract final class PartOfSpeechResolver {
  static final Map<String, ResolvedPartOfSpeech> _knownTags = {
    'n': const ResolvedPartOfSpeech(label: 'Noun', localizationKey: 'noun'),
    'pn': const ResolvedPartOfSpeech(
      label: 'Pronoun',
      localizationKey: 'pronoun',
    ),
    'pref': const ResolvedPartOfSpeech(
      label: 'Prefix',
      localizationKey: 'prefix',
    ),
    'suf': const ResolvedPartOfSpeech(
      label: 'Suffix',
      localizationKey: 'suffix',
    ),
    'ctr': const ResolvedPartOfSpeech(
      label: 'Counter',
      localizationKey: 'counter',
    ),
    'num': const ResolvedPartOfSpeech(
      label: 'Numeric',
      localizationKey: 'numeric',
    ),
    'exp': const ResolvedPartOfSpeech(
      label: 'Expression',
      localizationKey: 'expression',
    ),
    'int': const ResolvedPartOfSpeech(
      label: 'Interjection',
      localizationKey: 'interjection',
    ),
    'conj': const ResolvedPartOfSpeech(
      label: 'Conjunction',
      localizationKey: 'conjunction',
    ),
    'prt': const ResolvedPartOfSpeech(
      label: 'Particle',
      localizationKey: 'particle',
    ),
    'cop': const ResolvedPartOfSpeech(
      label: 'Copula',
      localizationKey: 'copula',
    ),
    'aux': const ResolvedPartOfSpeech(
      label: 'Auxiliary',
      localizationKey: 'auxiliary',
    ),
    'aux-v': const ResolvedPartOfSpeech(
      label: 'Auxiliary verb',
      localizationKey: 'auxiliaryVerb',
    ),
    'aux-adj': const ResolvedPartOfSpeech(
      label: 'Auxiliary adjective',
      localizationKey: 'auxiliaryAdjective',
    ),
    'adj-i': const ResolvedPartOfSpeech(
      label: 'I-adjective',
      localizationKey: 'iAdjective',
    ),
    'adj-na': const ResolvedPartOfSpeech(
      label: 'Na-adjective',
      localizationKey: 'naAdjective',
    ),
    'adj-no': const ResolvedPartOfSpeech(
      label: 'No-adjective',
      localizationKey: 'noAdjective',
    ),
    'adj-pn': const ResolvedPartOfSpeech(
      label: 'Pre-noun adjectival',
      localizationKey: 'preNounAdjectival',
    ),
    'adv': const ResolvedPartOfSpeech(
      label: 'Adverb',
      localizationKey: 'adverb',
    ),
    'adv-to': const ResolvedPartOfSpeech(
      label: 'To-adverb',
      localizationKey: 'toAdverb',
    ),
    'n-adv': const ResolvedPartOfSpeech(
      label: 'Adverbial noun',
      localizationKey: 'adverbialNoun',
    ),
    'vs': const ResolvedPartOfSpeech(
      label: 'Suru verb',
      localizationKey: 'suruVerb',
    ),
    'vs-s': const ResolvedPartOfSpeech(
      label: 'Suru verb',
      localizationKey: 'suruVerb',
    ),
    'vs-i': const ResolvedPartOfSpeech(
      label: 'Suru verb',
      localizationKey: 'suruVerb',
    ),
    'vk': const ResolvedPartOfSpeech(
      label: 'Kuru verb',
      localizationKey: 'kuruVerb',
    ),
    'v1': const ResolvedPartOfSpeech(
      label: 'Ichidan verb',
      localizationKey: 'ichidanVerb',
    ),
    'v1-s': const ResolvedPartOfSpeech(
      label: 'Ichidan verb',
      localizationKey: 'ichidanVerb',
    ),
    'vz': const ResolvedPartOfSpeech(
      label: 'Zuru verb',
      localizationKey: 'zuruVerb',
    ),
    'vi': const ResolvedPartOfSpeech(
      label: 'Intransitive verb',
      localizationKey: 'intransitiveVerb',
    ),
    'vt': const ResolvedPartOfSpeech(
      label: 'Transitive verb',
      localizationKey: 'transitiveVerb',
    ),
  };

  static final Set<String> _noiseTags = {
    'p',
    'uk',
    'ok',
    'ik',
    'io',
    'col',
    'arch',
    'obs',
    'rare',
    'abbr',
    'sl',
    'vulg',
    'vulgar',
    'hon',
    'hum',
    'pol',
    'fem',
    'masc',
  };

  static List<ResolvedPartOfSpeech> resolve(DictionaryEntry entry) {
    final resolved = <ResolvedPartOfSpeech>[];
    final seen = <String>{};

    for (final token in _extractTokens(entry)) {
      final normalized = token.toLowerCase();
      final item = _resolveToken(normalized, originalToken: token);
      if (item == null) continue;

      final dedupeKey = item.localizationKey ?? item.label.toLowerCase();
      if (seen.add(dedupeKey)) {
        resolved.add(item);
      }
    }

    return resolved;
  }

  static List<String> resolveLabels(DictionaryEntry entry) {
    return resolve(entry).map((item) => item.label).toList(growable: false);
  }

  static Iterable<String> _extractTokens(DictionaryEntry entry) sync* {
    for (final rawField in [
      entry.rules,
      entry.definitionTags,
      entry.termTags,
    ]) {
      if (rawField.trim().isEmpty) continue;
      final normalized = rawField
          .replaceAll('/', ' ')
          .replaceAll(';', ' ')
          .replaceAll(',', ' ')
          .replaceAll('|', ' ')
          .replaceAll('\u3000', ' ');
      for (final token in normalized.split(RegExp(r'\s+'))) {
        final trimmed = token.trim();
        if (trimmed.isNotEmpty) {
          yield trimmed;
        }
      }
    }
  }

  static ResolvedPartOfSpeech? _resolveToken(
    String token, {
    required String originalToken,
  }) {
    if (token.isEmpty || _isNoiseTag(token)) return null;

    final known = _knownTags[token];
    if (known != null) return known;

    if (_isGodanToken(token)) {
      return const ResolvedPartOfSpeech(
        label: 'Godan verb',
        localizationKey: 'godanVerb',
      );
    }

    if (_looksLikePosToken(token)) {
      return ResolvedPartOfSpeech(label: originalToken);
    }

    return null;
  }

  static bool _isGodanToken(String token) {
    return RegExp(r'^v5[a-z0-9-]*$').hasMatch(token);
  }

  static bool _isNoiseTag(String token) {
    return _noiseTags.contains(token) ||
        RegExp(r'^nf\d+$').hasMatch(token) ||
        RegExp(r'^(ichi|spec|gai)\d+$').hasMatch(token) ||
        RegExp(r'^(news|freq)\d*$').hasMatch(token) ||
        RegExp(r'^jlpt-n\d+$').hasMatch(token) ||
        RegExp(r'^wanikani\d+$').hasMatch(token);
  }

  static bool _looksLikePosToken(String token) {
    if (token.startsWith('adj') ||
        token.startsWith('adv') ||
        token.startsWith('aux') ||
        token.startsWith('conj') ||
        token.startsWith('cop') ||
        token.startsWith('ctr') ||
        token.startsWith('exp') ||
        token.startsWith('int') ||
        token.startsWith('num') ||
        token.startsWith('pn') ||
        token.startsWith('pref') ||
        token.startsWith('prt') ||
        token.startsWith('suf') ||
        token.startsWith('vi') ||
        token.startsWith('vk') ||
        token.startsWith('vs') ||
        token.startsWith('vt') ||
        token.startsWith('v1') ||
        token.startsWith('v5') ||
        token.startsWith('vz')) {
      return true;
    }

    return token == 'n' ||
        token.startsWith('n-') ||
        token.contains('noun') ||
        token.contains('verb') ||
        token.contains('adjective') ||
        token.contains('adverb') ||
        token.contains('particle') ||
        token.contains('pronoun') ||
        token.contains('prefix') ||
        token.contains('suffix') ||
        token.contains('counter') ||
        token.contains('interjection') ||
        token.contains('conjunction') ||
        token.contains('copula') ||
        token.contains('expression');
  }
}
