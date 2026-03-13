import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

/// Renders definition text with Japanese words highlighted and tappable.
///
/// Japanese character sequences are detected and segmented into individual
/// words via MeCab (when available). Each word gets its own tap recognizer.
/// Falls back to treating entire Japanese runs as single tappable units
/// when MeCab is not initialized.
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
      _rebuildSegments();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _disposeRecognizers();
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
            final recognizer = TapGestureRecognizer()
              ..onTap = () => widget.onWordTap(token);
            _recognizers.add(recognizer);
            segments.add(_DefinitionTextSegment(token, recognizer: recognizer));
          }
        } else {
          final recognizer = TapGestureRecognizer()
            ..onTap = () => widget.onWordTap(japaneseText);
          _recognizers.add(recognizer);
          segments.add(
            _DefinitionTextSegment(japaneseText, recognizer: recognizer),
          );
        }
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onWordTap(japaneseText);
        _recognizers.add(recognizer);
        segments.add(
          _DefinitionTextSegment(japaneseText, recognizer: recognizer),
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
      (segment) => segment.recognizer != null,
    );
    if (!hasTappableSegments) {
      return Text(widget.text, style: baseStyle);
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: _segments
            .map((segment) {
              return TextSpan(
                text: segment.text,
                style: segment.recognizer == null ? baseStyle : tapStyle,
                recognizer: segment.recognizer,
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _DefinitionTextSegment {
  const _DefinitionTextSegment(this.text, {this.recognizer});

  final String text;
  final TapGestureRecognizer? recognizer;
}
