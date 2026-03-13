import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class TextTapTarget {
  const TextTapTarget({
    required this.start,
    required this.end,
    required this.value,
  });

  final int start;
  final int end;
  final String value;
}

/// Renders a [RichText] while delegating all tap handling through one
/// [GestureDetector]. Taps are resolved by mapping the pointer location to
/// selection boxes from the laid-out [RenderParagraph].
class HitTestableRichText extends StatefulWidget {
  const HitTestableRichText({
    super.key,
    required this.text,
    required this.targets,
    required this.onTapTarget,
    this.textAlign = TextAlign.start,
    this.softWrap = true,
  });

  final TextSpan text;
  final List<TextTapTarget> targets;
  final ValueChanged<String> onTapTarget;
  final TextAlign textAlign;
  final bool softWrap;

  @override
  State<HitTestableRichText> createState() => _HitTestableRichTextState();
}

class _HitTestableRichTextState extends State<HitTestableRichText> {
  final GlobalKey _richTextKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: _handleTap,
      child: RichText(
        key: _richTextKey,
        text: widget.text,
        textAlign: widget.textAlign,
        softWrap: widget.softWrap,
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      ),
    );
  }

  void _handleTap(TapUpDetails details) {
    if (widget.targets.isEmpty) return;

    final renderObject = _richTextKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return;

    final localPosition = renderObject.globalToLocal(details.globalPosition);

    for (final target in widget.targets) {
      final boxes = renderObject.getBoxesForSelection(
        TextSelection(baseOffset: target.start, extentOffset: target.end),
      );
      for (final box in boxes) {
        if (box.toRect().inflate(4).contains(localPosition)) {
          widget.onTapTarget(target.value);
          return;
        }
      }
    }
  }
}
