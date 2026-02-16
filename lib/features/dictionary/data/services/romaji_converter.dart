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
    'wi': 'ゐ',
    'we': 'ゑ',
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
    'jo': 'じょ',
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
    'nn': 'ん',
    // 1-char vowels
    'a': 'あ',
    'i': 'い',
    'u': 'う',
    'e': 'え',
    'o': 'お',
  };

  /// Returns `true` if [text] looks like romaji (ASCII letters only).
  static bool isRomaji(String text) {
    if (text.isEmpty) return false;
    return _romajiPattern.hasMatch(text);
  }

  static final _romajiPattern = RegExp(r'^[a-zA-Z]+$');

  /// Convert [romaji] to hiragana. Non-convertible trailing characters
  /// are stripped so the result is pure hiragana suitable for prefix search.
  static String convert(String romaji) {
    final input = romaji.toLowerCase();
    final buffer = StringBuffer();
    var i = 0;

    while (i < input.length) {
      // Double consonant → っ (not 'n', which is handled by 'nn' mapping)
      if (i + 1 < input.length &&
          input[i] == input[i + 1] &&
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

      // Single char: only 'n' needs special handling
      if (input[i] == 'n') {
        // 'n' at end of string or before a consonant (not vowel/y) → ん
        if (i + 1 >= input.length) {
          buffer.write('ん');
          i++;
          continue;
        }
        final next = input[i + 1];
        if (!_vowels.contains(next) && next != 'y') {
          buffer.write('ん');
          i++;
          continue;
        }
        // 'n' before vowel/y: don't consume yet — could be na, ni, nya, etc.
        // but we already tried 2-char match above and it failed,
        // so this shouldn't normally happen. Treat as trailing.
        break;
      }

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
}
