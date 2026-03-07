import 'package:flutter/material.dart';
import 'package:mekuru/features/dictionary/data/services/kanji_reading_parser.dart';

class KanjiReadingsBlock extends StatelessWidget {
  const KanjiReadingsBlock({
    super.key,
    required this.data,
    this.labelStyle,
    this.readingStyle,
  });

  final KanjiEntryDisplayData data;
  final TextStyle? labelStyle;
  final TextStyle? readingStyle;

  @override
  Widget build(BuildContext context) {
    if (!data.hasReadings) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final resolvedLabelStyle =
        labelStyle ??
        theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        );
    final resolvedReadingStyle =
        readingStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.onyomi.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Onyomi: ', style: resolvedLabelStyle),
                TextSpan(
                  text: data.onyomi.join(', '),
                  style: resolvedReadingStyle,
                ),
              ],
            ),
          ),
        if (data.onyomi.isNotEmpty && data.kunyomi.isNotEmpty)
          const SizedBox(height: 2),
        if (data.kunyomi.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Kunyomi: ', style: resolvedLabelStyle),
                TextSpan(
                  text: data.kunyomi.join(', '),
                  style: resolvedReadingStyle,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
