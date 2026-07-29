import 'package:mekuru/core/utils/japanese_text.dart' as japanese_text;

/// Converts romaji text to hiragana for dictionary lookups.
///
/// Supports standard Hepburn romanization including:
/// - Basic syllables (ka, ki, ku, ke, ko, etc.)
/// - Palatalized sounds (kya, kyu, kyo, sha, chi, etc.)
/// - Double consonants (kk → っk, tt → っt, etc.)
/// - Syllabic n (n before consonant or end of string → ん)
class RomajiConverter {
  RomajiConverter._();

  static const _vowels = {'a', 'i', 'u', 'e', 'o'};

  // Ordered by length descending so longest match wins.
  static const _mappings = <String, String>{
    // 4-char
    'xtsu': 'っ',
    'ltsu': 'っ',
    // 3-char palatalized & special
    'sha': 'しゃ',
    'shi': 'し',
    'shu': 'しゅ',
    'she': 'しぇ',
    'sho': 'しょ',
    'chi': 'ち',
    'cha': 'ちゃ',
    'chu': 'ちゅ',
    'che': 'ちぇ',
    'cho': 'ちょ',
    'tsu': 'つ',
    'kya': 'きゃ',
    'kyu': 'きゅ',
    'kyo': 'きょ',
    'nya': 'にゃ',
    'nyu': 'にゅ',
    'nyo': 'にょ',
    'hya': 'ひゃ',
    'hyu': 'ひゅ',
    'hyo': 'ひょ',
    'mya': 'みゃ',
    'myu': 'みゅ',
    'myo': 'みょ',
    'rya': 'りゃ',
    'ryu': 'りゅ',
    'ryo': 'りょ',
    'gya': 'ぎゃ',
    'gyu': 'ぎゅ',
    'gyo': 'ぎょ',
    'jya': 'じゃ',
    'jyu': 'じゅ',
    'jyo': 'じょ',
    'bya': 'びゃ',
    'byu': 'びゅ',
    'byo': 'びょ',
    'pya': 'ぴゃ',
    'pyu': 'ぴゅ',
    'pyo': 'ぴょ',
    // Kunrei-shiki palatalized
    'sya': 'しゃ',
    'syu': 'しゅ',
    'syo': 'しょ',
    'tya': 'ちゃ',
    'tyu': 'ちゅ',
    'tyo': 'ちょ',
    'zya': 'じゃ',
    'zyu': 'じゅ',
    'zyo': 'じょ',
    'dya': 'ぢゃ',
    'dyu': 'ぢゅ',
    'dyo': 'ぢょ',
    // t/d + small vowel (パーティー-style loanwords)
    'tha': 'てゃ',
    'thi': 'てぃ',
    'thu': 'てゅ',
    'the': 'てぇ',
    'tho': 'てょ',
    'dha': 'でゃ',
    'dhi': 'でぃ',
    'dhu': 'でゅ',
    'dhe': 'でぇ',
    'dho': 'でょ',
    // w-row loanword sounds
    'wha': 'うぁ',
    'whi': 'うぃ',
    'whe': 'うぇ',
    'who': 'うぉ',
    // Small kana
    'xya': 'ゃ',
    'xyu': 'ゅ',
    'xyo': 'ょ',
    'lya': 'ゃ',
    'lyu': 'ゅ',
    'lyo': 'ょ',
    'xtu': 'っ',
    'ltu': 'っ',
    // 2-char basic syllables
    'ka': 'か',
    'ki': 'き',
    'ku': 'く',
    'ke': 'け',
    'ko': 'こ',
    'sa': 'さ',
    'si': 'し',
    'su': 'す',
    'se': 'せ',
    'so': 'そ',
    'ta': 'た',
    'ti': 'ち',
    'tu': 'つ',
    'te': 'て',
    'to': 'と',
    'na': 'な',
    'ni': 'に',
    'nu': 'ぬ',
    'ne': 'ね',
    'no': 'の',
    'ha': 'は',
    'hi': 'ひ',
    'hu': 'ふ',
    'fu': 'ふ',
    'he': 'へ',
    'ho': 'ほ',
    'ma': 'ま',
    'mi': 'み',
    'mu': 'む',
    'me': 'め',
    'mo': 'も',
    'ya': 'や',
    'yu': 'ゆ',
    'yo': 'よ',
    'ra': 'ら',
    'ri': 'り',
    'ru': 'る',
    're': 'れ',
    'ro': 'ろ',
    'wa': 'わ',
    // Wapuro convention: wi/we produce うぃ/うぇ (ウィスキー), not the
    // archaic ゐ/ゑ, matching what IMEs and jisho.org do.
    'wi': 'うぃ',
    'we': 'うぇ',
    'wo': 'を',
    'ga': 'が',
    'gi': 'ぎ',
    'gu': 'ぐ',
    'ge': 'げ',
    'go': 'ご',
    'za': 'ざ',
    'zi': 'じ',
    'zu': 'ず',
    'ze': 'ぜ',
    'zo': 'ぞ',
    'da': 'だ',
    'di': 'ぢ',
    'du': 'づ',
    'de': 'で',
    'do': 'ど',
    'ja': 'じゃ',
    'ju': 'じゅ',
    'je': 'じぇ',
    'jo': 'じょ',
    'ye': 'いぇ',
    // f-row and v-row loanword sounds
    'fa': 'ふぁ',
    'fi': 'ふぃ',
    'fe': 'ふぇ',
    'fo': 'ふぉ',
    'va': 'ゔぁ',
    'vi': 'ゔぃ',
    'vu': 'ゔ',
    've': 'ゔぇ',
    'vo': 'ゔぉ',
    // Small vowels
    'xa': 'ぁ',
    'xi': 'ぃ',
    'xu': 'ぅ',
    'xe': 'ぇ',
    'xo': 'ぉ',
    'la': 'ぁ',
    'li': 'ぃ',
    'lu': 'ぅ',
    'le': 'ぇ',
    'lo': 'ぉ',
    'ba': 'ば',
    'bi': 'び',
    'bu': 'ぶ',
    'be': 'べ',
    'bo': 'ぼ',
    'pa': 'ぱ',
    'pi': 'ぴ',
    'pu': 'ぷ',
    'pe': 'ぺ',
    'po': 'ぽ',
    // Note: 'nn' is NOT mapped here — single-n logic handles n-before-consonant,
    // which correctly emits ん and lets the second n start the next syllable.
    // 1-char vowels
    'a': 'あ',
    'i': 'い',
    'u': 'う',
    'e': 'え',
    'o': 'お',
  };

  /// Returns `true` if [text] looks like romaji: starts with an ASCII
  /// letter, followed by letters and the separators wapuro input uses —
  /// spaces ("ohayou gozaimasu"), hyphens for ー ("ka-do"), and apostrophes
  /// after ん ("kon'nichiwa").
  static bool isRomaji(String text) {
    if (text.isEmpty) return false;
    return _romajiPattern.hasMatch(text);
  }

  static final _romajiPattern = RegExp(r"^[a-zA-Z][a-zA-Z '\-]*$");

  /// Convert [romaji] to hiragana. Non-convertible trailing characters
  /// are stripped so the result is pure hiragana suitable for prefix search.
  /// Always the conventional reading — [convertAll]'s first candidate.
  static String convert(String romaji) =>
      convertAll(romaji, maxCandidates: 1).first;

  /// Every plausible hiragana reading of [romaji], conventional guess first.
  ///
  /// Romaji "n" is ambiguous before a vowel or y: "renai" can be れない or
  /// れんあい, and "rennai" can be れんない or れんあい. Candidates are
  /// enumerated depth-first taking the conventional interpretation first at
  /// every ambiguity point, so element 0 is always [convert]'s output and
  /// truncation under [maxCandidates] drops the least conventional readings
  /// first. Never returns an empty list.
  static List<String> convertAll(String romaji, {int maxCandidates = 16}) {
    final input = romaji.toLowerCase();
    final limit = maxCandidates < 1 ? 1 : maxCandidates;
    final out = <String>{}; // Insertion-ordered: keeps conventional first
    var paths = 1;

    bool tryFork() {
      if (paths >= limit) return false;
      paths++;
      return true;
    }

    void scan(int start, String acc) {
      var i = start;
      var kana = acc;

      while (i < input.length) {
        // Separators: spaces and apostrophes (syllable break after ん) are
        // skipped; a hyphen is wapuro input for the prolonged sound mark.
        final ch = input[i];
        if (ch == ' ' || ch == "'") {
          i++;
          continue;
        }
        if (ch == '-') {
          kana += 'ー';
          i++;
          continue;
        }

        // Syllabic n handling.
        // - "n" before consonant, apostrophe, or end -> ん (unambiguous)
        // - "nn" before vowel/y -> ん + な-row (onna → おんな), or ん
        //   absorbing both n's (rennai → れんあい)
        // - "nn" before consonant/end -> ん
        // - "n" before vowel/y -> な-row syllable (renai → れない), or ん +
        //   the vowel syllable (renai → れんあい) unless that would put ん at
        //   the start of the word or after another ん
        if (ch == 'n') {
          if (i + 1 >= input.length) {
            kana += 'ん';
            i++;
            continue;
          }

          final next = input[i + 1];
          if (next == 'n') {
            final ambiguous =
                i + 2 < input.length && _startsSyllableAfterN(input[i + 2]);
            if (ambiguous && tryFork()) {
              // Conventional subtree first: the second n starts the next
              // syllable. This path continues as ん absorbing both n's.
              scan(i + 1, '$kanaん');
              kana += 'ん';
              i += 2;
              continue;
            }
            kana += 'ん';
            // Out of budget, the ambiguous case stays conventional: leave
            // the second n to the next iteration, where the no-んん rule
            // forces the な-row.
            i += ambiguous ? 1 : 2;
            continue;
          }
          if (!_startsSyllableAfterN(next)) {
            kana += 'ん';
            i++;
            continue;
          }
          // n before vowel/y: falls through so the syllable is consumed
          // only once, whether or not the fork below is taken.
        }

        final chunk = _consumeSyllable(input, i);
        if (ch == 'n' &&
            chunk != null &&
            kana.isNotEmpty &&
            !kana.endsWith('ん') &&
            tryFork()) {
          // Conventional subtree first: the な-row syllable. This path
          // continues as the ん + vowel alternative.
          scan(i + chunk.length, kana + chunk.kana);
          kana += 'ん';
          i++;
          continue;
        }
        if (chunk == null) break; // Unrecognized — drop trailing partial
        kana += chunk.kana;
        i += chunk.length;
      }

      out.add(kana);
    }

    scan(0, '');
    return out.toList();
  }

  /// A vowel or y — what makes a preceding n ambiguous.
  static bool _startsSyllableAfterN(String c) =>
      _vowels.contains(c) || c == 'y';

  /// Consume one non-ん syllable at [i]: sokuon, then longest mapping match
  /// (4 → 2 chars), then a single character. Returns null on an unrecognized
  /// character.
  static ({String kana, int length})? _consumeSyllable(String input, int i) {
    // Double consonant → っ (not 'n', which the syllabic-n logic owns;
    // only ASCII letters qualify — repeated separators are not sokuon)
    if (i + 1 < input.length &&
        input[i] == input[i + 1] &&
        _isAsciiLetter(input[i]) &&
        !_vowels.contains(input[i]) &&
        input[i] != 'n') {
      return (kana: 'っ', length: 1);
    }

    // Try longest match first: 4, 3, 2 chars
    for (var len = 4; len >= 2; len--) {
      if (i + len > input.length) continue;
      final kana = _mappings[input.substring(i, i + len)];
      if (kana != null) return (kana: kana, length: len);
    }

    // Single vowel
    final single = _mappings[input[i]];
    if (single != null) return (kana: single, length: 1);

    return null;
  }

  /// Convert katakana characters to hiragana (offset 0x60). Delegates to
  /// the shared [japanese_text.katakanaToHiragana]. Kept as a stable API:
  /// benchmark/jmdict_eval_test.dart pins this name across commits.
  static String katakanaToHiragana(String text) =>
      japanese_text.katakanaToHiragana(text);

  /// Convert hiragana characters to katakana (offset 0x60). Loanwords are
  /// stored in katakana in Yomitan dictionaries, so hiragana and romaji
  /// input needs a katakana variant to reach カード-style entries.
  static String hiraganaToKatakana(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0x3041 && rune <= 0x3096) {
        buffer.writeCharCode(rune + 0x60);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Collapse long vowels in [katakana] into the prolonged sound mark:
  /// repeated vowels (カアド → カード) plus the standard digraphs エイ → エー
  /// and オウ → オー. ン and ッ break the vowel run. Katakana loanwords are
  /// written with ー, so a phonetic spelling (kaado → カアド) needs this
  /// variant to match カード.
  static String collapseKatakanaLongVowels(String katakana) {
    final buffer = StringBuffer();
    String? vowelClass;
    for (final rune in katakana.runes) {
      if (rune == 0x30FC) {
        // ー: keep, and the vowel run continues through it.
        buffer.writeCharCode(rune);
        continue;
      }

      final standalone = switch (rune) {
        0x30A2 => 'a',
        0x30A4 => 'i',
        0x30A6 => 'u',
        0x30A8 => 'e',
        0x30AA => 'o',
        _ => null,
      };
      if (standalone != null &&
          vowelClass != null &&
          (standalone == vowelClass ||
              (standalone == 'i' && vowelClass == 'e') ||
              (standalone == 'u' && vowelClass == 'o'))) {
        buffer.write('ー');
        continue;
      }

      buffer.writeCharCode(rune);
      vowelClass = _kanaVowelClass[japanese_text.katakanaRuneToHiragana(rune)];
    }
    return buffer.toString();
  }

  /// Vowel class of each kana, derived from [_mappings] (the romaji key's
  /// final letter names the vowel of the mapping's final kana). っ is
  /// excluded — it carries no vowel for long-vowel purposes.
  static final Map<int, String> _kanaVowelClass = _buildKanaVowelClass();

  static Map<int, String> _buildKanaVowelClass() {
    final map = <int, String>{};
    _mappings.forEach((romaji, kana) {
      final vowel = romaji[romaji.length - 1];
      if (!_vowels.contains(vowel)) return;
      map[kana.runes.last] = vowel;
    });
    map.remove(0x3063); // っ
    return map;
  }

  /// True if [kana] ends in a kana whose vowel a following う lengthens —
  /// the お-row and う-row, excluding う itself (うう is never a long-vowel
  /// spelling). The inverse question of [collapseKatakanaLongVowels],
  /// answered from the same [_mappings]-derived vowel table.
  static bool endsInLongVowelStarter(String kana) {
    if (kana.isEmpty) return false;
    final last = kana.runes.last;
    if (last == 0x3046) return false; // う
    final vowel = _kanaVowelClass[last];
    return vowel == 'o' || vowel == 'u';
  }

  static bool _isAsciiLetter(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x61 && code <= 0x7A; // input is lowercased before use
  }
}
