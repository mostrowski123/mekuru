/// Groups the text lines Apple Vision finds on a manga page into blocks
/// (speech bubbles, captions). iOS only: there the platform detector stands in
/// for the Android comic-text-detector, which also did this grouping.
///
/// Written from scratch for Vision's output; nothing here derives from the
/// Android detector code. Pure logic, no Flutter imports.
library;

import 'dart:math' as math;

/// One text line as Vision reports it, in page pixels (origin top-left).
class VisionLine {
  const VisionLine({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.text,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final String text;

  double get width => right - left;
  double get height => bottom - top;

  /// A column of vertical text is taller than wide. A single character is
  /// roughly square either way, and manga is mostly vertical, so ties and
  /// one-character lines count as vertical until a neighbour says otherwise.
  bool get looksVertical => text.runes.length < 2 || height >= width;

  /// Character size: a vertical column is one character wide, a horizontal
  /// line one character tall.
  double get fontSize => looksVertical ? width : height;
}

/// Lines that belong together, in reading order.
class VisionBlock {
  const VisionBlock({required this.lines, required this.vertical});

  /// Right to left for vertical text, top to bottom for horizontal.
  final List<VisionLine> lines;
  final bool vertical;

  double get left => lines.map((l) => l.left).reduce(math.min);
  double get top => lines.map((l) => l.top).reduce(math.min);
  double get right => lines.map((l) => l.right).reduce(math.max);
  double get bottom => lines.map((l) => l.bottom).reduce(math.max);

  /// Median character size of the block's lines.
  double get fontSize {
    final sizes = lines.map((l) => l.fontSize).toList()..sort();
    return sizes[sizes.length ~/ 2];
  }
}

/// How far apart two neighbouring lines of one block may be, in character
/// sizes of the smaller line. Columns in a bubble sit well under one character
/// apart; separate bubbles are further.
const _maxGapInChars = 0.9;

/// Lines of one block start near the same edge or overlap along the reading
/// direction; this is how much of the shorter line must overlap.
const _minOverlap = 0.3;

/// Ruby (furigana) is set at about half the size of the text it annotates.
const _rubySizeRatio = 0.6;

List<VisionBlock> groupVisionLines(List<VisionLine> lines) {
  final kept = _withoutRuby(
    lines.where((l) => l.text.trim().isNotEmpty).toList(),
  );

  // Union-find over lines that are neighbours in the same block.
  final parent = List<int>.generate(kept.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  for (var i = 0; i < kept.length; i++) {
    for (var j = i + 1; j < kept.length; j++) {
      if (_sameBlock(kept[i], kept[j])) parent[find(i)] = find(j);
    }
  }

  final groups = <int, List<VisionLine>>{};
  for (var i = 0; i < kept.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(kept[i]);
  }

  final blocks = [for (final group in groups.values) _block(group)];
  // Page reading order for manga: top to bottom, right to left within a row.
  blocks.sort((a, b) {
    final rowHeight = math.max(a.fontSize, b.fontSize) * 2;
    if ((a.top - b.top).abs() > rowHeight) return a.top.compareTo(b.top);
    return b.right.compareTo(a.right);
  });
  return blocks;
}

VisionBlock _block(List<VisionLine> lines) {
  // Longer lines say more about the direction than one stray character.
  var verticalWeight = 0;
  var horizontalWeight = 0;
  for (final line in lines) {
    final weight = line.text.runes.length;
    if (weight < 2) continue;
    line.looksVertical ? verticalWeight += weight : horizontalWeight += weight;
  }
  final vertical = verticalWeight >= horizontalWeight;
  final ordered = [...lines]
    ..sort(
      (a, b) => vertical ? b.right.compareTo(a.right) : a.top.compareTo(b.top),
    );
  return VisionBlock(lines: ordered, vertical: vertical);
}

bool _sameBlock(VisionLine a, VisionLine b) {
  final size = math.min(a.fontSize, b.fontSize);
  // Text of very different sizes is a different voice (a shout beside a
  // whisper, a caption beside dialogue), even when it touches.
  if (math.max(a.fontSize, b.fontSize) > size * 2) return false;

  final bothMultiChar = a.text.runes.length >= 2 && b.text.runes.length >= 2;
  if (bothMultiChar && a.looksVertical != b.looksVertical) return false;
  final vertical = a.text.runes.length >= 2 ? a.looksVertical : b.looksVertical;

  final double gap;
  final double overlap;
  final double shorter;
  if (vertical) {
    // Columns side by side: gap across, overlap along the column.
    gap = math.max(a.left, b.left) - math.min(a.right, b.right);
    overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    shorter = math.min(a.height, b.height);
  } else {
    gap = math.max(a.top, b.top) - math.min(a.bottom, b.bottom);
    overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
    shorter = math.min(a.width, b.width);
  }
  return gap <= size * _maxGapInChars && overlap >= shorter * _minOverlap;
}

/// Drops ruby: a much smaller line hugging a larger one. Reading it as text
/// of its own would put the reading of a word beside the word.
List<VisionLine> _withoutRuby(List<VisionLine> lines) {
  bool isRubyOf(VisionLine small, VisionLine base) {
    if (small.fontSize > base.fontSize * _rubySizeRatio) return false;
    final gap = base.looksVertical
        ? math.max(small.left, base.left) - math.min(small.right, base.right)
        : math.max(small.top, base.top) - math.min(small.bottom, base.bottom);
    final overlap = base.looksVertical
        ? math.min(small.bottom, base.bottom) - math.max(small.top, base.top)
        : math.min(small.right, base.right) - math.max(small.left, base.left);
    return gap <= small.fontSize * 0.5 && overlap > 0;
  }

  return [
    for (final line in lines)
      if (!lines.any(
        (other) => !identical(other, line) && isRubyOf(line, other),
      ))
        line,
  ];
}
