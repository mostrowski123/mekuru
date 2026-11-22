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

  /// Formats the animated value (e.g. minutes → "3h 20m"). Defaults to the
  /// bare number, with no grouping.
  final String Function(int value)? formatter;

  String _format(int shown) => formatter?.call(shown) ?? '$shown';

  TextStyle? _numberStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);

  /// Whether every word of the final number fits [width] at the user's text
  /// size, so the number never breaks inside a word ("12.3" over "K").
  bool fitsWidth(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: _format(value),
        style: DefaultTextStyle.of(context).style.merge(_numberStyle(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final fits = painter.minIntrinsicWidth <= width;
    painter.dispose();
    return fits;
  }

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
            // A long duration ("120h 45m") or a large text scale can outgrow
            // a third of a phone screen. The number wraps between its words
            // then, at the size the user chose; a row whose numbers would
            // break inside a word stacks its tiles (see [fitsWidth]).
            Text(
              _format(shown),
              textAlign: TextAlign.center,
              style: _numberStyle(context),
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
