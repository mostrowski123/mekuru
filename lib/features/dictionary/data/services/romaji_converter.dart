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
  static String convert(String romaji) {
    final input = romaji.toLowerCase();
    final buffer = StringBuffer();
    var i = 0;

    while (i < input.length) {
      // Separators: spaces and apostrophes (syllable break after ん) are
      // skipped; a hyphen is wapuro input for the prolonged sound mark.
      final ch = input[i];
      if (ch == ' ' || ch == "'") {
        i++;
        continue;
      }
      if (ch == '-') {
        buffer.write('ー');
        i++;
        continue;
      }

      // Syllabic n handling.
      // - "n" before consonant or end -> ん
      // - "nn" before vowel/y -> first n becomes ん, second starts next syllable
      // - "nn" before consonant/end -> ん
      if (input[i] == 'n') {
        if (i + 1 >= input.length) {
          buffer.write('ん');
          i++;
          continue;
        }

        final next = input[i + 1];
        if (next == 'n') {
          if (i + 2 < input.length) {
            final next2 = input[i + 2];
            if (_vowels.contains(next2) || next2 == 'y') {
              buffer.write('ん');
              i++;
              continue;
            }
          }
          buffer.write('ん');
          i += 2;
          continue;
        }

        if (!_vowels.contains(next) && next != 'y') {
          buffer.write('ん');
          i++;
          continue;
        }
      }

      // Double consonant → っ (not 'n', which is handled by 'nn' mapping;
      // only ASCII letters qualify — repeated separators are not sokuon)
      if (i + 1 < input.length &&
          input[i] == input[i + 1] &&
          _isAsciiLetter(input[i]) &&
          !_vowels.contains(input[i]) &&
          input[i] != 'n') {
        buffer.write('っ');
        i++;
        continue;
      }

      // Try longest match first: 4, 3, 2 chars
      var matched = false;
      for (var len = 4; len >= 2; len--) {
        if (i + len > input.length) continue;
        final substr = input.substring(i, i + len);
        final kana = _mappings[substr];
        if (kana != null) {
          buffer.write(kana);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // Single vowel
      final singleKana = _mappings[input[i]];
      if (singleKana != null) {
        buffer.write(singleKana);
        i++;
        continue;
      }

      // Unrecognized character — stop (trailing partial syllable)
      break;
    }

    return buffer.toString();
  }

  /// Convert katakana characters to hiragana (offset 0x60).
  static String katakanaToHiragana(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        buffer.writeCharCode(rune - 0x60);
      } else if (rune == 0x30FC) {
        // ー (katakana prolonged sound mark) — keep as-is
        buffer.writeCharCode(rune);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

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
      final hiragana = (rune >= 0x30A1 && rune <= 0x30F6) ? rune - 0x60 : rune;
      vowelClass = _kanaVowelClass[hiragana];
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

  static bool _isAsciiLetter(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x61 && code <= 0x7A; // input is lowercased before use
  }
}
