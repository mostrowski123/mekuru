import 'package:flutter/material.dart';

class SourceSectionLabel extends StatelessWidget {
  const SourceSectionLabel({
    super.key,
    required this.label,
    this.topPadding = 4,
    this.bottomPadding = 4,
    this.fontSize,
  });

  final String label;
  final double topPadding;
  final double bottomPadding;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.15,
      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
    );

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(label, style: labelStyle, textAlign: TextAlign.end),
      ),
    );
  }
}
