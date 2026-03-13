import 'package:flutter/material.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

/// Displays a Japanese expression with furigana only above kanji, where each
/// kanji character is individually tappable.
///
/// Kana portions are rendered as plain text at the normal baseline. Kanji
/// characters are styled to indicate tappability, and a single gesture handler
/// resolves which kanji was tapped.
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
  List<_ExpressionSegmentCache> _segmentCache = const [];
  bool _showFurigana = false;
  List<_ExpressionTapTargetRect>? _furiganaTapTargetsCache;

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
  void didUpdateWidget(TappableExpressionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression ||
        oldWidget.reading != widget.reading) {
      _rebuildSegmentCache();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
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

    _furiganaTapTargetsCache = null;
  }

  List<_ExpressionGlyphCache> _buildGlyphCache(String text) {
    final glyphs = <_ExpressionGlyphCache>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      glyphs.add(
        _ExpressionGlyphCache(char, isTappable: _isKanji(char.codeUnitAt(0))),
      );
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
            style: glyph.isTappable ? kanjiStyle : baseStyle,
          );
        })
        .toList(growable: false);
  }

  List<TextTapTarget> _buildFlatTargets(List<_ExpressionGlyphCache> glyphs) {
    final targets = <TextTapTarget>[];
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      if (!glyph.isTappable) continue;
      targets.add(TextTapTarget(start: i, end: i + 1, value: glyph.char));
    }
    return targets;
  }

  void _handleFuriganaTap(
    Offset localPosition, {
    required TextStyle? expressionStyle,
    required TextStyle? kanjiStyle,
    required TextStyle? furiganaStyle,
  }) {
    _furiganaTapTargetsCache ??= _buildFuriganaTapTargets(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      expressionStyle: expressionStyle,
      kanjiStyle: kanjiStyle,
      furiganaStyle: furiganaStyle,
    );

    for (final target in _furiganaTapTargetsCache!) {
      if (target.rect.inflate(4).contains(localPosition)) {
        widget.onKanjiTap(target.char);
        return;
      }
    }
  }

  List<_ExpressionTapTargetRect> _buildFuriganaTapTargets({
    required TextDirection textDirection,
    required TextScaler textScaler,
    required TextStyle? expressionStyle,
    required TextStyle? kanjiStyle,
    required TextStyle? furiganaStyle,
  }) {
    final metrics = _segmentCache
        .map(
          (segment) => _measureExpressionSegment(
            segment,
            textDirection: textDirection,
            textScaler: textScaler,
            expressionStyle: expressionStyle,
            kanjiStyle: kanjiStyle,
            furiganaStyle: furiganaStyle,
          ),
        )
        .toList(growable: false);

    final rowHeight = metrics.fold<double>(
      0,
      (maxHeight, metric) =>
          metric.height > maxHeight ? metric.height : maxHeight,
    );

    final targets = <_ExpressionTapTargetRect>[];
    var dx = 0.0;
    for (final metric in metrics) {
      final baseX = dx + (metric.width - metric.baseSize.width) / 2;
      final baseY = rowHeight - metric.baseSize.height;
      for (final target in metric.targets) {
        targets.add(
          _ExpressionTapTargetRect(
            char: target.char,
            rect: target.rect.shift(Offset(baseX, baseY)),
          ),
        );
      }
      dx += metric.width;
    }

    return targets;
  }

  _MeasuredExpressionSegment _measureExpressionSegment(
    _ExpressionSegmentCache segment, {
    required TextDirection textDirection,
    required TextScaler textScaler,
    required TextStyle? expressionStyle,
    required TextStyle? kanjiStyle,
    required TextStyle? furiganaStyle,
  }) {
    final basePainter = TextPainter(
      text: TextSpan(
        children: _buildCharSpans(segment.glyphs, expressionStyle, kanjiStyle),
        style: expressionStyle,
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    TextPainter? furiganaPainter;
    if (segment.furigana != null) {
      furiganaPainter = TextPainter(
        text: TextSpan(text: segment.furigana!, style: furiganaStyle),
        textDirection: textDirection,
        textScaler: textScaler,
        textAlign: TextAlign.center,
      )..layout();
    }

    final targets = <_ExpressionTapTargetRect>[];
    for (var i = 0; i < segment.glyphs.length; i++) {
      final glyph = segment.glyphs[i];
      if (!glyph.isTappable) continue;
      final boxes = basePainter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      for (final box in boxes) {
        targets.add(
          _ExpressionTapTargetRect(char: glyph.char, rect: box.toRect()),
        );
      }
    }

    final width = furiganaPainter == null
        ? basePainter.width
        : (furiganaPainter.width > basePainter.width
              ? furiganaPainter.width
              : basePainter.width);
    final height = basePainter.height + (furiganaPainter?.height ?? 0);

    final result = _MeasuredExpressionSegment(
      width: width,
      height: height,
      baseSize: basePainter.size,
      targets: targets,
    );

    basePainter.dispose();
    furiganaPainter?.dispose();

    return result;
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

      return HitTestableRichText(
        text: TextSpan(
          children: _buildCharSpans(glyphs, exprStyle, kanjiStyle),
          style: exprStyle,
        ),
        targets: _buildFlatTargets(glyphs),
        onTapTarget: widget.onKanjiTap,
      );
    }

    final furiStyle =
        widget.furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) => _handleFuriganaTap(
        details.localPosition,
        expressionStyle: exprStyle,
        kanjiStyle: kanjiStyle,
        furiganaStyle: furiStyle,
      ),
      child: Row(
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
      ),
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
  const _ExpressionGlyphCache(this.char, {required this.isTappable});

  final String char;
  final bool isTappable;
}

class _ExpressionTapTargetRect {
  const _ExpressionTapTargetRect({required this.char, required this.rect});

  final String char;
  final Rect rect;
}

class _MeasuredExpressionSegment {
  const _MeasuredExpressionSegment({
    required this.width,
    required this.height,
    required this.baseSize,
    required this.targets,
  });

  final double width;
  final double height;
  final Size baseSize;
  final List<_ExpressionTapTargetRect> targets;
}
