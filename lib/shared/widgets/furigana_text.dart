import 'package:flutter/material.dart';

/// Displays a Japanese expression with furigana (reading) above it.
///
/// If [reading] is empty or matches [expression], only the expression is shown.
/// Otherwise the reading appears in small text above the expression.
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

  /// Style for the furigana (reading) text above. If null, derived from
  /// [expressionStyle] at 55% size.
  final TextStyle? furiganaStyle;

  @override
  Widget build(BuildContext context) {
    final showFurigana =
        reading.isNotEmpty && reading != expression;

    final exprStyle = expressionStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            );

    if (!showFurigana) {
      return Text(expression, style: exprStyle);
    }

    final furiStyle = furiganaStyle ??
        exprStyle?.copyWith(
          fontSize: (exprStyle.fontSize ?? 16) * 0.55,
          fontWeight: FontWeight.w400,
          height: 1.0,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(reading, style: furiStyle),
        Text(expression, style: exprStyle),
      ],
    );
  }
}
