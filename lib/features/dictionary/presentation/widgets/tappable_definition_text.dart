import 'package:flutter/material.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
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
  List<TapSegment> _segments = const [];

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
    _segments = tapSegments(widget.text);
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

/// A piece of definition text; [tapValue] is set for a tappable Japanese word.
class TapSegment {
  const TapSegment(this.text, {this.tapValue});

  final String text;
  final String? tapValue;
}

/// Splits [text] into tappable Japanese words (MeCab tokens, or whole
/// Japanese runs when MeCab is not initialized) and the text between them.
List<TapSegment> tapSegments(String text) {
  final segments = <TapSegment>[];
  final mecab = MecabService.instance;
  var lastEnd = 0;

  for (final match in japaneseRunPattern.allMatches(text)) {
    if (match.start > lastEnd) {
      segments.add(TapSegment(text.substring(lastEnd, match.start)));
    }

    final japaneseText = match.group(0)!;
    final tokens = mecab.isInitialized
        ? mecab.tokenize(japaneseText)
        : const <String>[];
    if (tokens.join() == japaneseText) {
      for (final token in tokens) {
        segments.add(TapSegment(token, tapValue: token));
      }
    } else {
      segments.add(TapSegment(japaneseText, tapValue: japaneseText));
    }

    lastEnd = match.end;
  }

  if (lastEnd < text.length) {
    segments.add(TapSegment(text.substring(lastEnd)));
  }
  return segments;
}
