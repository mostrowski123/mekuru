import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

/// Displays a Japanese expression with furigana only above kanji, where each
/// kanji character is individually tappable.
///
/// Kana portions are rendered as plain text at the normal baseline. Kanji
/// characters get tap recognizers and are styled to indicate tappability.
///
/// If [reading] is empty or matches [expression], only the expression is shown.
class TappableExpressionText extends StatefulWidget {
  const TappableExpressionText({
    super.key,
    required this.expression,
    required this.reading,
    required this.onKanjiTap,
    this.expressionStyle,
    this.furiganaStyle,
  });

  final String expression;
  final String reading;
  final void Function(String kanji) onKanjiTap;
  final TextStyle? expressionStyle;
  final TextStyle? furiganaStyle;

  @override
  State<TappableExpressionText> createState() =>
      _TappableExpressionTextState();
}

class _TappableExpressionTextState extends State<TappableExpressionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  static bool _isKanji(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(TappableExpressionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression) {
      _disposeRecognizers();
    }
  }

  /// Build per-character spans for a text segment, making kanji tappable.
  List<InlineSpan> _buildCharSpans(
    String text,
    TextStyle? baseStyle,
    TextStyle? kanjiStyle,
  ) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isKanji(char.codeUnitAt(0))) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onKanjiTap(char);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: char,
          style: kanjiStyle,
          recognizer: recognizer,
        ));
      } else {
        spans.add(TextSpan(text: char, style: baseStyle));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final theme = Theme.of(context);
    final showFurigana =
        widget.reading.isNotEmpty && widget.reading != widget.expression;

    final exprStyle = widget.expressionStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            );

    final kanjiStyle = exprStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: theme.colorScheme.primary.withAlpha(100),
    );

    if (!showFurigana) {
      // No furigana: render expression as a flat Text.rich with tappable kanji.
      return Text.rich(
        TextSpan(
          children: _buildCharSpans(widget.expression, exprStyle, kanjiStyle),
          style: exprStyle,
        ),
      );
    }

    final furiStyle = widget.furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    final segments = segmentFurigana(widget.expression, widget.reading);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.furigana != null) {
          // Kanji segment: furigana above, tappable kanji below.
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                seg.furigana!,
                style: furiStyle,
                textAlign: TextAlign.center,
              ),
              Text.rich(
                TextSpan(
                  children:
                      _buildCharSpans(seg.text, exprStyle, kanjiStyle),
                  style: exprStyle,
                ),
              ),
            ],
          );
        }
        // Kana segment: plain text with tappable kanji detection
        // (rare, but handles edge cases like 々).
        return Text.rich(
          TextSpan(
            children: _buildCharSpans(seg.text, exprStyle, kanjiStyle),
            style: exprStyle,
          ),
        );
      }).toList(),
    );
  }
}
