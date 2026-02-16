import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Displays a Japanese expression with furigana, where each kanji character
/// is individually tappable.
///
/// Kanji characters (CJK Unified Ideographs) get tap recognizers and are
/// styled to indicate tappability. Non-kanji characters (hiragana, katakana,
/// punctuation) are rendered as plain text.
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

    // Build per-character spans for the expression
    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.expression.length; i++) {
      final char = widget.expression[i];
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
        spans.add(TextSpan(text: char));
      }
    }

    final expressionWidget = Text.rich(
      TextSpan(children: spans, style: exprStyle),
    );

    if (!showFurigana) {
      return expressionWidget;
    }

    final furiStyle = widget.furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.reading, style: furiStyle),
        expressionWidget,
      ],
    );
  }
}
