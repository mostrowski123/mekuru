import 'package:flutter/material.dart';

/// A segment of text that may have furigana (reading) displayed above it.
class FuriganaSegment {
  /// The base text (a kanji run or kana run).
  final String text;

  /// The reading shown above [text]. Non-null only for kanji segments.
  final String? furigana;

  const FuriganaSegment(this.text, [this.furigana]);
}

/// Splits [expression] and [reading] into segments where furigana only
/// appears above kanji characters, matching standard Ruby text conventions.
///
/// Examples:
/// - expression="行く" reading="いく" → [("行","い"), ("く",null)]
/// - expression="食べる" reading="たべる" → [("食","た"), ("べる",null)]
/// - expression="血液" reading="けつえき" → [("血液","けつえき")]
/// - expression="お金持ち" reading="おかねもち" → [("お",null), ("金持","かねも"), ("ち",null)]
///
/// When alignment fails (e.g., mismatched expression/reading), falls back
/// to a single segment with the full reading above the full expression.
List<FuriganaSegment> segmentFurigana(String expression, String reading) {
  if (reading.isEmpty || reading == expression) {
    return [FuriganaSegment(expression)];
  }

  // If expression has no kanji, no furigana is needed.
  if (!expression.runes.any(_isKanji)) {
    return [FuriganaSegment(expression)];
  }

  final hiraReading = _katakanaToHiragana(reading);

  // Try alignment; fall back to full-expression furigana on failure.
  final segments = _alignSegments(expression, hiraReading);
  if (segments.isEmpty) {
    return [FuriganaSegment(expression, reading)];
  }
  return segments;
}

bool _isKanji(int codeUnit) {
  return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
}

String _katakanaToHiragana(String input) {
  final buf = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buf.writeCharCode(rune - 0x60);
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

/// Convert a single character to its hiragana equivalent (for alignment).
String _charToHiragana(String char) {
  final code = char.codeUnitAt(0);
  if (code >= 0x30A1 && code <= 0x30F6) {
    return String.fromCharCode(code - 0x60);
  }
  return char;
}

/// Walk through [expression] and [hiraReading] in parallel, producing
/// segments with kanji-only furigana. Returns empty list if alignment fails.
List<FuriganaSegment> _alignSegments(String expression, String hiraReading) {
  final segments = <FuriganaSegment>[];
  int ri = 0; // current position in hiraReading
  int i = 0; // current position in expression

  while (i < expression.length) {
    final code = expression.codeUnitAt(i);

    if (!_isKanji(code)) {
      // Kana run: collect consecutive non-kanji characters.
      final start = i;
      while (
          i < expression.length && !_isKanji(expression.codeUnitAt(i))) {
        i++;
      }
      final kanaRun = expression.substring(start, i);
      segments.add(FuriganaSegment(kanaRun));
      // Advance reading pointer past the matching kana.
      ri += kanaRun.length;
    } else {
      // Kanji run: collect consecutive kanji.
      final kanjiStart = i;
      while (
          i < expression.length && _isKanji(expression.codeUnitAt(i))) {
        i++;
      }
      final kanjiRun = expression.substring(kanjiStart, i);

      if (i < expression.length) {
        // There are characters after the kanji run. Find where the next
        // non-kanji expression character appears in the remaining reading
        // to determine the furigana boundary.
        final nextExprHira = _charToHiragana(expression[i]);

        int matchPos = -1;
        for (int j = ri; j < hiraReading.length; j++) {
          if (hiraReading[j] == nextExprHira) {
            matchPos = j;
            break;
          }
        }

        if (matchPos > ri) {
          final furi = hiraReading.substring(ri, matchPos);
          segments.add(FuriganaSegment(kanjiRun, furi));
          ri = matchPos;
        } else if (matchPos == ri) {
          // Kanji has no reading characters (unusual) — emit without furigana.
          segments.add(FuriganaSegment(kanjiRun));
        } else {
          // Alignment failed.
          return [];
        }
      } else {
        // Kanji run at end of expression: all remaining reading is furigana.
        if (ri < hiraReading.length) {
          final furi = hiraReading.substring(ri);
          segments.add(FuriganaSegment(kanjiRun, furi));
          ri = hiraReading.length;
        } else {
          segments.add(FuriganaSegment(kanjiRun));
        }
      }
    }
  }

  return segments;
}

/// Displays a Japanese expression with furigana (reading) only above kanji.
///
/// Kana portions of the expression are displayed at the normal baseline
/// without furigana, matching standard Ruby text conventions.
///
/// If [reading] is empty or matches [expression], only the expression is shown.
class FuriganaText extends StatelessWidget {
  const FuriganaText({
    super.key,
    required this.expression,
    required this.reading,
    this.expressionStyle,
    this.furiganaStyle,
  });

  final String expression;
  final String reading;

  /// Style for the main expression text.
  final TextStyle? expressionStyle;

  /// Style for the furigana (reading) text above kanji. If null, derived from
  /// [expressionStyle] at 55% size.
  final TextStyle? furiganaStyle;

  @override
  Widget build(BuildContext context) {
    final showFurigana = reading.isNotEmpty && reading != expression;

    final exprStyle = expressionStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            );

    if (!showFurigana) {
      return Text(expression, style: exprStyle);
    }

    final furiStyle = furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    final segments = segmentFurigana(expression, reading);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.furigana != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                seg.furigana!,
                style: furiStyle,
                textAlign: TextAlign.center,
              ),
              Text(seg.text, style: exprStyle),
            ],
          );
        }
        return Text(seg.text, style: exprStyle);
      }).toList(),
    );
  }
}
