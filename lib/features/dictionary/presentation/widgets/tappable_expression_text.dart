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
  State<TappableExpressionText> createState() => _TappableExpressionTextState();
}

class _TappableExpressionTextState extends State<TappableExpressionText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<_ExpressionSegmentCache> _segmentCache = const [];
  bool _showFurigana = false;

  static bool _isKanji(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
  }

  @override
  void initState() {
    super.initState();
    _rebuildSegmentCache();
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
    if (oldWidget.expression != widget.expression ||
        oldWidget.reading != widget.reading) {
      _disposeRecognizers();
      _rebuildSegmentCache();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _disposeRecognizers();
    _rebuildSegmentCache();
  }

  void _rebuildSegmentCache() {
    _showFurigana =
        widget.reading.isNotEmpty && widget.reading != widget.expression;

    final rawSegments = _showFurigana
        ? segmentFurigana(widget.expression, widget.reading)
        : [FuriganaSegment(widget.expression)];

    _segmentCache = rawSegments
        .map((segment) {
          return _ExpressionSegmentCache(
            text: segment.text,
            furigana: segment.furigana,
            glyphs: _buildGlyphCache(segment.text),
          );
        })
        .toList(growable: false);
  }

  List<_ExpressionGlyphCache> _buildGlyphCache(String text) {
    final glyphs = <_ExpressionGlyphCache>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isKanji(char.codeUnitAt(0))) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onKanjiTap(char);
        _recognizers.add(recognizer);
        glyphs.add(_ExpressionGlyphCache(char, recognizer: recognizer));
      } else {
        glyphs.add(_ExpressionGlyphCache(char));
      }
    }
    return glyphs;
  }

  List<InlineSpan> _buildCharSpans(
    List<_ExpressionGlyphCache> glyphs,
    TextStyle? baseStyle,
    TextStyle? kanjiStyle,
  ) {
    return glyphs
        .map((glyph) {
          return TextSpan(
            text: glyph.char,
            style: glyph.recognizer == null ? baseStyle : kanjiStyle,
            recognizer: glyph.recognizer,
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final exprStyle =
        widget.expressionStyle ??
        Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);

    final kanjiStyle = exprStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: theme.colorScheme.primary.withAlpha(100),
    );

    if (!_showFurigana) {
      final glyphs = _segmentCache.isEmpty
          ? const <_ExpressionGlyphCache>[]
          : _segmentCache.first.glyphs;
      return Text.rich(
        TextSpan(
          children: _buildCharSpans(glyphs, exprStyle, kanjiStyle),
          style: exprStyle,
        ),
      );
    }

    final furiStyle =
        widget.furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: _segmentCache
          .map((segment) {
            if (segment.furigana != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    segment.furigana!,
                    style: furiStyle,
                    textAlign: TextAlign.center,
                  ),
                  Text.rich(
                    TextSpan(
                      children: _buildCharSpans(
                        segment.glyphs,
                        exprStyle,
                        kanjiStyle,
                      ),
                      style: exprStyle,
                    ),
                  ),
                ],
              );
            }

            return Text.rich(
              TextSpan(
                children: _buildCharSpans(
                  segment.glyphs,
                  exprStyle,
                  kanjiStyle,
                ),
                style: exprStyle,
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ExpressionSegmentCache {
  const _ExpressionSegmentCache({
    required this.text,
    required this.furigana,
    required this.glyphs,
  });

  final String text;
  final String? furigana;
  final List<_ExpressionGlyphCache> glyphs;
}

class _ExpressionGlyphCache {
  const _ExpressionGlyphCache(this.char, {this.recognizer});

  final String char;
  final TapGestureRecognizer? recognizer;
}
