// Two-page spread layout calculator for manga reading.
//
// Computes how pages are grouped into spreads (single or two-page) from
// their sizes, their declared spread sides, and the reading direction.
//
// Pure functions — no Flutter widget dependencies, fully unit-testable.

import 'package:mekuru/features/manga/data/models/mokuro_models.dart';

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
  int get primaryPageIndex => (leftPageIndex != null && rightPageIndex != null)
      ? (leftPageIndex! < rightPageIndex! ? leftPageIndex! : rightPageIndex!)
      : (leftPageIndex ?? rightPageIndex ?? 0);

  /// Returns true if this spread contains [pageIndex].
  bool containsPage(int pageIndex) =>
      leftPageIndex == pageIndex || rightPageIndex == pageIndex;

  @override
  String toString() =>
      'PageSpread(left: $leftPageIndex, right: $rightPageIndex)';

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
/// - A page declared [MangaPageSpread.center] stands alone, and so does a
///   wide page (wider than tall) when [detectWidePages] is on.
/// - A page declared on the opening side (right for right-to-left books,
///   left otherwise) opens a pair; the next page joins it unless it stands
///   alone or opens a pair itself. A closing-side page with no opener before
///   it stands alone.
/// - Undeclared pages pair up in order: the cover stands alone, then (1,2),
///   (3,4)…, restarting after a page that stands alone.
/// - [shift] moves every pair by one page: the cover pairs with page 1, a
///   run after a lone page starts with a single page, and the declared
///   sides swap roles.
/// - For RTL: right page = lower index, left page = higher index.
/// - For LTR: left page = lower index, right page = higher index.
List<PageSpread> computeSpreads(
  List<MokuroPage> pages, {
  required bool isRtl,
  bool detectWidePages = true,
  bool shift = false,
}) {
  bool alone(MokuroPage page) =>
      page.spread == MangaPageSpread.center ||
      (detectWidePages && page.imgHeight > 0 && page.imgWidth > page.imgHeight);
  final opener = isRtl != shift ? MangaPageSpread.right : MangaPageSpread.left;
  final closer = isRtl != shift ? MangaPageSpread.left : MangaPageSpread.right;

  final spreads = <PageSpread>[];
  var leadSingle = !shift;
  var i = 0;
  while (i < pages.length) {
    final page = pages[i];
    final next = i + 1 < pages.length ? pages[i + 1] : null;
    final single =
        alone(page) ||
        page.spread == closer ||
        (page.spread == null && leadSingle) ||
        next == null ||
        alone(next) ||
        next.spread == opener;
    if (single) {
      spreads.add(
        isRtl ? PageSpread(rightPageIndex: i) : PageSpread(leftPageIndex: i),
      );
      leadSingle = alone(page) && shift;
      i += 1;
    } else {
      spreads.add(
        isRtl
            ? PageSpread(leftPageIndex: i + 1, rightPageIndex: i)
            : PageSpread(leftPageIndex: i, rightPageIndex: i + 1),
      );
      leadSingle = false;
      i += 2;
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
