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
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      codeUnit == 0x3005 || // 々 iteration mark
      codeUnit == 0x3006 || // 〆
      codeUnit == 0x30F5 || // ヵ
      codeUnit == 0x30F6; // ヶ
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

/// Walk through [expression] and [hiraReading] in parallel, producing
/// segments with kanji-only furigana. Returns empty list if alignment fails.
List<FuriganaSegment> _alignSegments(String expression, String hiraReading) {
  final memo = <(int, int), List<FuriganaSegment>?>{};
  return _alignSegmentsFrom(expression, hiraReading, 0, 0, memo) ?? [];
}

List<FuriganaSegment>? _alignSegmentsFrom(
  String expression,
  String hiraReading,
  int expressionIndex,
  int readingIndex,
  Map<(int, int), List<FuriganaSegment>?> memo,
) {
  final key = (expressionIndex, readingIndex);
  if (memo.containsKey(key)) {
    return memo[key];
  }

  if (expressionIndex == expression.length) {
    final result = readingIndex == hiraReading.length
        ? const <FuriganaSegment>[]
        : null;
    memo[key] = result;
    return result;
  }

  final code = expression.codeUnitAt(expressionIndex);

  if (!_isKanji(code)) {
    // Kana run: it must line up exactly with the remaining reading.
    final start = expressionIndex;
    var end = expressionIndex;
    while (end < expression.length && !_isKanji(expression.codeUnitAt(end))) {
      end++;
    }

    final kanaRun = expression.substring(start, end);
    final normalizedKanaRun = _katakanaToHiragana(kanaRun);

    if (!hiraReading.startsWith(normalizedKanaRun, readingIndex)) {
      memo[key] = null;
      return null;
    }

    final rest = _alignSegmentsFrom(
      expression,
      hiraReading,
      end,
      readingIndex + normalizedKanaRun.length,
      memo,
    );
    if (rest == null) {
      memo[key] = null;
      return null;
    }

    final result = [FuriganaSegment(kanaRun), ...rest];
    memo[key] = result;
    return result;
  }

  // Kanji run: try all possible furigana boundaries that allow the rest of
  // the expression to align, instead of greedily taking the first kana match.
  final kanjiStart = expressionIndex;
  var kanjiEnd = expressionIndex;
  while (kanjiEnd < expression.length &&
      _isKanji(expression.codeUnitAt(kanjiEnd))) {
    kanjiEnd++;
  }

  final kanjiRun = expression.substring(kanjiStart, kanjiEnd);
  if (kanjiEnd == expression.length) {
    final furigana = readingIndex < hiraReading.length
        ? hiraReading.substring(readingIndex)
        : null;
    final result = [FuriganaSegment(kanjiRun, furigana)];
    memo[key] = result;
    return result;
  }

  var nextKanaEnd = kanjiEnd;
  while (nextKanaEnd < expression.length &&
      !_isKanji(expression.codeUnitAt(nextKanaEnd))) {
    nextKanaEnd++;
  }

  final nextKanaRun = expression.substring(kanjiEnd, nextKanaEnd);
  final normalizedNextKanaRun = _katakanaToHiragana(nextKanaRun);

  for (
    var boundary = readingIndex + 1;
    boundary <= hiraReading.length - normalizedNextKanaRun.length;
    boundary++
  ) {
    if (!hiraReading.startsWith(normalizedNextKanaRun, boundary)) {
      continue;
    }

    final rest = _alignSegmentsFrom(
      expression,
      hiraReading,
      kanjiEnd,
      boundary,
      memo,
    );
    if (rest == null) {
      continue;
    }

    final result = [
      FuriganaSegment(kanjiRun, hiraReading.substring(readingIndex, boundary)),
      ...rest,
    ];
    memo[key] = result;
    return result;
  }

  if (hiraReading.startsWith(normalizedNextKanaRun, readingIndex)) {
    final rest = _alignSegmentsFrom(
      expression,
      hiraReading,
      kanjiEnd,
      readingIndex,
      memo,
    );
    if (rest != null) {
      final result = [FuriganaSegment(kanjiRun), ...rest];
      memo[key] = result;
      return result;
    }
  }

  memo[key] = null;
  return null;
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

    final exprStyle =
        expressionStyle ??
        Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);

    if (!showFurigana) {
      return Text(expression, style: exprStyle);
    }

    final furiStyle =
        furiganaStyle ??
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
