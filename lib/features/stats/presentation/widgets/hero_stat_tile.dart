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
          children: [
            // Only the number scales: counts condense before they get long,
            // but a long duration ("120h 45m") or a large text scale can
            // still outgrow a third of a phone screen — the label, though,
            // must keep the user's text scale rather than shrink with it.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatter?.call(shown) ?? '$shown',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
