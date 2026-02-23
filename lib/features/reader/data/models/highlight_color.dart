import 'dart:ui';

/// Available highlight colors for text annotations.
enum HighlightColor {
  yellow(Color(0xFFFFEB3B), 'yellow'),
  blue(Color(0xFF64B5F6), 'blue'),
  green(Color(0xFF81C784), 'green'),
  pink(Color(0xFFF48FB1), 'pink');

  const HighlightColor(this.color, this.name);

  final Color color;
  final String name;

  /// Look up a [HighlightColor] by its stored name string.
  static HighlightColor fromName(String name) {
    return HighlightColor.values.firstWhere(
      (c) => c.name == name,
      orElse: () => HighlightColor.yellow,
    );
  }
}
