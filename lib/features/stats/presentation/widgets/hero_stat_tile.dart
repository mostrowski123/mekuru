import 'package:flutter/material.dart';

/// Large headline stat with a one-shot count-up entrance.
class HeroStatTile extends StatelessWidget {
  const HeroStatTile({
    super.key,
    required this.label,
    required this.value,
    this.formatter,
  });

  final String label;
  final int value;

  /// Formats the animated value (e.g. minutes → "3h 20m"). Defaults to
  /// plain grouping.
  final String Function(int value)? formatter;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final shown = (value * t).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatter?.call(shown) ?? '$shown',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
