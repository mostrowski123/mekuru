import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Renders definition text with Japanese words highlighted and tappable.
///
/// Japanese character sequences (kanji, hiragana, katakana) are detected
/// and wrapped with tap recognizers. When tapped, [onWordTap] is called
/// with the tapped word, enabling drill-down dictionary lookups.
class TappableDefinitionText extends StatefulWidget {
  const TappableDefinitionText({
    super.key,
    required this.text,
    required this.onWordTap,
    this.style,
    this.tappableStyle,
  });

  final String text;
  final void Function(String word) onWordTap;
  final TextStyle? style;
  final TextStyle? tappableStyle;

  @override
  State<TappableDefinitionText> createState() => _TappableDefinitionTextState();
}

class _TappableDefinitionTextState extends State<TappableDefinitionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  // Matches runs of Japanese characters:
  // - Kanji (CJK Unified Ideographs + Extension A)
  // - Hiragana
  // - Katakana
  // - Katakana prolonged sound mark (ー)
  // - CJK iteration marks (々)
  static final _japanesePattern = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\u3400-\u4DBF\u30FC\u3005]+',
  );

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
  void didUpdateWidget(TappableDefinitionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final theme = Theme.of(context);
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final tapStyle = widget.tappableStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary.withAlpha(100),
        );

    final spans = <InlineSpan>[];
    final matches = _japanesePattern.allMatches(widget.text);
    var lastEnd = 0;

    for (final match in matches) {
      // Add non-Japanese text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: widget.text.substring(lastEnd, match.start)));
      }

      final japaneseText = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWordTap(japaneseText);
      _recognizers.add(recognizer);

      spans.add(TextSpan(
        text: japaneseText,
        style: tapStyle,
        recognizer: recognizer,
      ));

      lastEnd = match.end;
    }

    // Add remaining non-Japanese text
    if (lastEnd < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      return Text(widget.text, style: baseStyle);
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
    );
  }
}
