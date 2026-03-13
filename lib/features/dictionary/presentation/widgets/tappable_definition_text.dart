import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';

/// Renders definition text with Japanese words highlighted and tappable.
///
/// Japanese character sequences are detected and segmented into individual
/// words via MeCab (when available). Taps are resolved through a single
/// hit-testable text widget instead of per-word recognizers.
/// Falls back to treating entire Japanese runs as single tappable units when
/// MeCab is not initialized.
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
  List<_DefinitionTextSegment> _segments = const [];

  // Matches runs of Japanese characters:
  // - Kanji (CJK Unified Ideographs + Extension A)
  // - Hiragana
  // - Katakana
  // - Katakana prolonged sound mark (U+30FC)
  // - CJK iteration mark (U+3005)
  static final _japanesePattern = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\u3400-\u4DBF\u30FC\u3005]+',
  );

  @override
  void initState() {
    super.initState();
    _rebuildSegments();
  }

  @override
  void didUpdateWidget(TappableDefinitionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _rebuildSegments();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _rebuildSegments();
  }

  void _rebuildSegments() {
    final segments = <_DefinitionTextSegment>[];
    final matches = _japanesePattern.allMatches(widget.text);
    var lastEnd = 0;

    final mecab = MecabService.instance;

    for (final match in matches) {
      if (match.start > lastEnd) {
        segments.add(
          _DefinitionTextSegment(widget.text.substring(lastEnd, match.start)),
        );
      }

      final japaneseText = match.group(0)!;

      if (mecab.isInitialized) {
        final tokens = mecab.tokenize(japaneseText);
        final reconstructed = tokens.join();
        if (reconstructed == japaneseText) {
          for (final token in tokens) {
            segments.add(_DefinitionTextSegment(token, tapValue: token));
          }
        } else {
          segments.add(
            _DefinitionTextSegment(japaneseText, tapValue: japaneseText),
          );
        }
      } else {
        segments.add(
          _DefinitionTextSegment(japaneseText, tapValue: japaneseText),
        );
      }

      lastEnd = match.end;
    }

    if (lastEnd < widget.text.length) {
      segments.add(_DefinitionTextSegment(widget.text.substring(lastEnd)));
    }

    _segments = segments;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final tapStyle =
        widget.tappableStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary.withAlpha(100),
        );

    if (_segments.isEmpty) {
      return Text(widget.text, style: baseStyle);
    }

    final hasTappableSegments = _segments.any(
      (segment) => segment.tapValue != null,
    );
    if (!hasTappableSegments) {
      return Text(widget.text, style: baseStyle);
    }

    var offset = 0;
    final targets = <TextTapTarget>[];
    final children = _segments
        .map((segment) {
          final start = offset;
          offset += segment.text.length;
          if (segment.tapValue != null) {
            targets.add(
              TextTapTarget(
                start: start,
                end: offset,
                value: segment.tapValue!,
              ),
            );
          }

          return TextSpan(
            text: segment.text,
            style: segment.tapValue == null ? baseStyle : tapStyle,
          );
        })
        .toList(growable: false);

    return HitTestableRichText(
      text: TextSpan(style: baseStyle, children: children),
      targets: targets,
      onTapTarget: widget.onWordTap,
    );
  }
}

class _DefinitionTextSegment {
  const _DefinitionTextSegment(this.text, {this.tapValue});

  final String text;
  final String? tapValue;
}
