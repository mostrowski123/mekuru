// Two-page spread layout calculator for manga reading.
//
// Computes how pages should be grouped into spreads (single or two-page)
// based on total page count and reading direction. Page 0 (cover) is always
// shown alone; remaining pages are paired sequentially.
//
// Pure functions — no Flutter dependencies, fully unit-testable.

/// A single spread in the manga reader — either one page (cover/trailing)
/// or two pages side by side.
class PageSpread {
  /// Left-side page index (null if this is a right-only single spread).
  final int? leftPageIndex;

  /// Right-side page index (null if this is a left-only single spread).
  final int? rightPageIndex;

  const PageSpread({this.leftPageIndex, this.rightPageIndex});

  /// True if only one page is shown (cover or trailing odd page).
  bool get isSinglePage => leftPageIndex == null || rightPageIndex == null;

  /// The "primary" page index — the single page, or the lower-numbered page.
  int get primaryPageIndex =>
      (leftPageIndex != null && rightPageIndex != null)
          ? (leftPageIndex! < rightPageIndex! ? leftPageIndex! : rightPageIndex!)
          : (leftPageIndex ?? rightPageIndex ?? 0);

  /// Returns true if this spread contains [pageIndex].
  bool containsPage(int pageIndex) =>
      leftPageIndex == pageIndex || rightPageIndex == pageIndex;

  @override
  String toString() => 'PageSpread(left: $leftPageIndex, right: $rightPageIndex)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageSpread &&
          leftPageIndex == other.leftPageIndex &&
          rightPageIndex == other.rightPageIndex;

  @override
  int get hashCode => Object.hash(leftPageIndex, rightPageIndex);
}

/// Compute spread layout for a manga book.
///
/// Rules:
/// - Page 0 (cover) is always displayed alone.
/// - Remaining pages are paired sequentially: (1,2), (3,4), etc.
/// - If a trailing page has no partner, it's shown alone.
/// - For RTL: right page = lower index, left page = higher index.
/// - For LTR: left page = lower index, right page = higher index.
List<PageSpread> computeSpreads(int totalPages, {required bool isRtl}) {
  if (totalPages <= 0) return [];

  final spreads = <PageSpread>[];

  // Cover page always solo — placed on the side matching reading direction.
  if (isRtl) {
    spreads.add(const PageSpread(rightPageIndex: 0));
  } else {
    spreads.add(const PageSpread(leftPageIndex: 0));
  }

  // Pair remaining pages
  int i = 1;
  while (i < totalPages) {
    if (i + 1 < totalPages) {
      final lower = i;
      final higher = i + 1;
      if (isRtl) {
        spreads.add(PageSpread(leftPageIndex: higher, rightPageIndex: lower));
      } else {
        spreads.add(PageSpread(leftPageIndex: lower, rightPageIndex: higher));
      }
      i += 2;
    } else {
      // Trailing odd page — solo
      if (isRtl) {
        spreads.add(PageSpread(rightPageIndex: i));
      } else {
        spreads.add(PageSpread(leftPageIndex: i));
      }
      i++;
    }
  }

  return spreads;
}

/// Find which spread index contains [pageIndex].
///
/// Returns 0 if not found (shouldn't happen for valid page indices).
int spreadIndexForPage(List<PageSpread> spreads, int pageIndex) {
  for (int i = 0; i < spreads.length; i++) {
    if (spreads[i].containsPage(pageIndex)) return i;
  }
  return 0;
}
