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
  const VisionBlock({
    required this.lines,
    required this.vertical,
    this.rubyLines = const [],
  });

  /// Right to left for vertical text, top to bottom for horizontal.
  final List<VisionLine> lines;

  /// The ruby (furigana) annotating [lines]. Not text of its own: it is here
  /// so the bounds cover it, and nowhere else.
  final List<VisionLine> rubyLines;

  final bool vertical;

  /// Bounds cover the ruby too. manga-ocr reads the crop these bounds make and
  /// was trained to ignore furigana inside it, so leaving the ruby out only
  /// clips the edge of the bubble off the crop and costs accuracy.
  Iterable<VisionLine> get _extent => lines.followedBy(rubyLines);

  double get left => _extent.map((l) => l.left).reduce(math.min);
  double get top => _extent.map((l) => l.top).reduce(math.min);
  double get right => _extent.map((l) => l.right).reduce(math.max);
  double get bottom => _extent.map((l) => l.bottom).reduce(math.max);

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

/// A block's lines fill most of its bounds. Two bubbles chained into one
/// through a line that sits near both leave a hole, so a block this empty is
/// grouped again with a tighter gap, which tells them apart.
const _minFill = 0.6;

/// How much tighter each re-grouping is, and how tight it may get: below this
/// the columns of one bubble start to come apart.
const _splitGapFactor = 0.5;
const _minGapInChars = 0.2;

/// Ruby (furigana) is set at about half the size of the text it annotates.
const _rubySizeRatio = 0.6;

/// Ruby annotates a word, not a whole column, so it runs well short of the
/// line it sits beside. A neighbouring column of smaller text runs the length
/// of the bubble and is text, not ruby.
const _rubySpanRatio = 0.8;

/// One text line and the ruby hanging off it. They travel together, so a
/// re-grouping never has to work out the ruby again.
class _Unit {
  _Unit(this.line);

  final VisionLine line;
  final List<VisionLine> ruby = [];
}

List<VisionBlock> groupVisionLines(List<VisionLine> lines) {
  final kept = dedupeVisionLines(
    lines.where((l) => l.text.trim().isNotEmpty).toList(),
  );
  // Ruby joins the block of the line it annotates and nothing else: reading it
  // as text of its own would put the reading of a word beside the word, and
  // letting it group freely would let it bridge two bubbles.
  final rubyBase = _rubyBases(kept);

  final units = <_Unit>[];
  final unitOfLine = <int, int>{};
  for (var i = 0; i < kept.length; i++) {
    if (rubyBase.containsKey(i)) continue;
    unitOfLine[i] = units.length;
    units.add(_Unit(kept[i]));
  }
  rubyBase.forEach((ruby, base) {
    // Ruby of a line that is itself ruby annotates no text, so it is dropped.
    final unit = unitOfLine[base];
    if (unit != null) units[unit].ruby.add(kept[ruby]);
  });

  final blocks = [
    for (final group in _cluster(units, _maxGapInChars))
      _block(
        [for (final u in group) u.line],
        [for (final u in group) ...u.ruby],
      ),
  ];
  // Page reading order for manga: top to bottom, right to left within a row.
  blocks.sort((a, b) {
    final rowHeight = math.max(a.fontSize, b.fontSize) * 2;
    if ((a.top - b.top).abs() > rowHeight) return a.top.compareTo(b.top);
    return b.right.compareTo(a.right);
  });
  return blocks;
}

/// Union-find over units that are neighbours, then a second look: a group
/// whose lines leave a hole in its bounds is two bubbles that chained through
/// a line near both, and is grouped again with a tighter gap.
List<List<_Unit>> _cluster(List<_Unit> units, double maxGap) {
  final parent = List<int>.generate(units.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  for (var i = 0; i < units.length; i++) {
    for (var j = i + 1; j < units.length; j++) {
      if (_sameBlock(units[i].line, units[j].line, maxGap)) {
        parent[find(i)] = find(j);
      }
    }
  }

  final groups = <int, List<_Unit>>{};
  for (var i = 0; i < units.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(units[i]);
  }

  final tighter = maxGap * _splitGapFactor;
  return [
    for (final group in groups.values)
      // Two lines that grouped are directly adjacent; it takes a third to
      // chain two bubbles together, and a short line beside a long one is a
      // real block that simply does not fill its bounds.
      if (group.length > 2 &&
          tighter >= _minGapInChars &&
          _fill(group) < _minFill)
        ..._cluster(group, tighter)
      else
        group,
  ];
}

/// How much of a group's bounds its lines actually cover.
double _fill(List<_Unit> group) {
  final lines = [
    for (final u in group) ...[u.line, ...u.ruby],
  ];
  final covered = lines.fold<double>(0, (sum, l) => sum + l.width * l.height);
  final width =
      lines.map((l) => l.right).reduce(math.max) -
      lines.map((l) => l.left).reduce(math.min);
  final height =
      lines.map((l) => l.bottom).reduce(math.max) -
      lines.map((l) => l.top).reduce(math.min);
  final bounds = width * height;
  return bounds <= 0 ? 1 : math.min(1, covered / bounds);
}

VisionBlock _block(List<VisionLine> lines, List<VisionLine> ruby) {
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
  return VisionBlock(lines: ordered, vertical: vertical, rubyLines: ruby);
}

bool _sameBlock(VisionLine a, VisionLine b, double maxGap) {
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
  return gap <= size * maxGap && overlap >= shorter * _minOverlap;
}

/// Finds the ruby: a much smaller line hugging a larger one. Maps the index of
/// each ruby line to the index of the line it annotates.
Map<int, int> _rubyBases(List<VisionLine> lines) {
  bool isRubyOf(VisionLine small, VisionLine base) {
    if (small.fontSize > base.fontSize * _rubySizeRatio) return false;
    final gap = base.looksVertical
        ? math.max(small.left, base.left) - math.min(small.right, base.right)
        : math.max(small.top, base.top) - math.min(small.bottom, base.bottom);
    final overlap = base.looksVertical
        ? math.min(small.bottom, base.bottom) - math.max(small.top, base.top)
        : math.min(small.right, base.right) - math.max(small.left, base.left);
    if (gap > small.fontSize * 0.5 || overlap <= 0) return false;
    // Along the reading direction: ruby stays inside the span of the line it
    // annotates, and covers only part of it.
    final (smallStart, smallEnd) = base.looksVertical
        ? (small.top, small.bottom)
        : (small.left, small.right);
    final (baseStart, baseEnd) = base.looksVertical
        ? (base.top, base.bottom)
        : (base.left, base.right);
    if (smallEnd - smallStart > (baseEnd - baseStart) * _rubySpanRatio) {
      return false;
    }
    final slack = small.fontSize;
    return smallStart >= baseStart - slack && smallEnd <= baseEnd + slack;
  }

  final bases = <int, int>{};
  for (var i = 0; i < lines.length; i++) {
    for (var j = 0; j < lines.length; j++) {
      if (i != j && isRubyOf(lines[i], lines[j])) {
        bases[i] = j;
        break;
      }
    }
  }
  return bases;
}

/// Drops lines that repeat one already in the list: a double-page spread is
/// read as two overlapping passes (`visionPasses` in `AppDelegate.swift`), so
/// a line on the gutter comes back from both. The first reading wins.
List<VisionLine> dedupeVisionLines(List<VisionLine> lines) {
  final kept = <VisionLine>[];
  for (final line in lines) {
    if (!kept.any((other) => _iou(line, other) >= _duplicateIou)) {
      kept.add(line);
    }
  }
  return kept;
}

/// Two boxes of the same line, found by two passes, land within a pixel or
/// two of each other; anything this close is the same line twice.
const _duplicateIou = 0.5;

double _iou(VisionLine a, VisionLine b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final overlap = w * h;
  final union = a.width * a.height + b.width * b.height - overlap;
  return union <= 0 ? 0 : overlap / union;
}
