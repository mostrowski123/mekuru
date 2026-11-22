import 'package:mekuru/features/reader/data/models/reader_settings.dart';

enum PageTransitionDirection { none, forward, backward }

enum ReaderNavigationIntent { none, toggleControls, goForward, goBackward }

const double kDefaultSwipeVelocityThreshold = 400.0;

/// Width fraction for the center toggle-controls zone (center 50% of screen).
const double kToggleZoneWidthFraction = 0.50;

/// Returns true if the tap is in the center zone used to toggle controls.
///
/// The zone spans the center [widthFraction] of the screen horizontally.
/// Any vertical position qualifies — only taps on the left/right edges
/// are used for page navigation.
bool isCenterTapZone({
  required double x,
  double widthFraction = kToggleZoneWidthFraction,
}) {
  assert(widthFraction > 0 && widthFraction < 1);

  final clampedX = x.clamp(0.0, 1.0);

  final zoneStart = (1.0 - widthFraction) / 2.0;
  final zoneEnd = zoneStart + widthFraction;

  return clampedX >= zoneStart && clampedX <= zoneEnd;
}

/// [inTopOrBottomMargin]: the tap landed in the page margin above or below
/// the text, which toggles the controls like the center zone.
/// [scrollView]: the book scrolls instead of turning pages, so edge taps
/// don't turn pages and a tap anywhere toggles the controls.
ReaderNavigationIntent resolveTapIntent({
  required double normalizedX,
  required double normalizedY,
  required ReaderDirection readingDirection,
  double centerZoneWidthFraction = kToggleZoneWidthFraction,
  bool inTopOrBottomMargin = false,
  bool scrollView = false,
}) {
  if (scrollView ||
      inTopOrBottomMargin ||
      isCenterTapZone(x: normalizedX, widthFraction: centerZoneWidthFraction)) {
    return ReaderNavigationIntent.toggleControls;
  }

  final isLeftSide = normalizedX < 0.5;
  if (isLeftSide) {
    return readingDirection == ReaderDirection.rtl
        ? ReaderNavigationIntent.goForward
        : ReaderNavigationIntent.goBackward;
  }

  return readingDirection == ReaderDirection.rtl
      ? ReaderNavigationIntent.goBackward
      : ReaderNavigationIntent.goForward;
}

ReaderNavigationIntent resolveSwipeIntent({
  required double velocityX,
  required ReaderDirection readingDirection,
  double velocityThreshold = kDefaultSwipeVelocityThreshold,
}) {
  if (velocityX.abs() < velocityThreshold) {
    return ReaderNavigationIntent.none;
  }

  return intentForHorizontalSwipe(
    towardRight: velocityX > 0,
    readingDirection: readingDirection,
  );
}

/// Maps a horizontal swipe's direction to a navigation intent: swiping toward
/// the right advances an RTL book and goes back in an LTR book.
ReaderNavigationIntent intentForHorizontalSwipe({
  required bool towardRight,
  required ReaderDirection readingDirection,
}) {
  final rtl = readingDirection == ReaderDirection.rtl;
  if (towardRight) {
    return rtl
        ? ReaderNavigationIntent.goForward
        : ReaderNavigationIntent.goBackward;
  }
  return rtl
      ? ReaderNavigationIntent.goBackward
      : ReaderNavigationIntent.goForward;
}

// ── Scroll view ─────────────────────────────────────────────────────

/// Where the scroll-view strip stood when a touch began. The bridge sends
/// it with every touchDown while scroll view is on, and null otherwise.
class ScrollEdges {
  const ScrollEdges({
    required this.horizontalAxis,
    required this.rtl,
    required this.atStart,
    required this.atEnd,
  });

  /// Parses the bridge's `{axis, dir, atStart, atEnd}` map. Anything else
  /// (paginated mode sends null) is null.
  static ScrollEdges? fromBridge(Object? data) {
    if (data is! Map) return null;
    return ScrollEdges(
      horizontalAxis: data['axis'] == 'horizontal',
      rtl: data['dir'] == 'rtl',
      atStart: data['atStart'] == true,
      atEnd: data['atEnd'] == true,
    );
  }

  /// True when the strip scrolls sideways (vertical text).
  final bool horizontalAxis;
  final bool rtl;
  final bool atStart;
  final bool atEnd;
}

/// Resolves a drag ([gesture] from [classifyGesture]) in scroll view. The
/// drag already scrolled the strip natively, so it only changes chapter when
/// it started with the strip at an edge and pushes past it. A fling that
/// merely reaches the end stays put. Vertical drags across a sideways strip
/// do nothing.
ReaderNavigationIntent resolveScrollViewSwipe({
  required GestureType gesture,
  required bool towardRight,
  required ScrollEdges edges,
}) {
  // The finger moves the way the text moves, as when turning pages sideways;
  // horizontal text comes in from below, so bottom to top is forward. A
  // sideways swipe also counts on a strip that scrolls up and down: it
  // scrolls nothing there, and a vertical book's image pages are laid out
  // that way (horizontal-tb), where readers keep swiping sideways.
  final intent = switch (gesture) {
    GestureType.horizontalSwipe => intentForHorizontalSwipe(
      towardRight: towardRight,
      readingDirection: edges.rtl ? ReaderDirection.rtl : ReaderDirection.ltr,
    ),
    _ when edges.horizontalAxis => ReaderNavigationIntent.none,
    GestureType.verticalSwipeUp => ReaderNavigationIntent.goForward,
    GestureType.verticalSwipeDown => ReaderNavigationIntent.goBackward,
    _ => ReaderNavigationIntent.none,
  };
  return switch (intent) {
    ReaderNavigationIntent.goForward when edges.atEnd => intent,
    ReaderNavigationIntent.goBackward when edges.atStart => intent,
    _ => ReaderNavigationIntent.none,
  };
}

// ── Gesture classification ──────────────────────────────────────────

/// Touch gesture types.
enum GestureType { tap, horizontalSwipe, verticalSwipeDown, verticalSwipeUp }

/// Threshold for classifying a touch as a swipe (fraction of screen dimension).
const double kSwipeDistanceThreshold = 0.1;

/// Classifies a touch interaction as a tap, horizontal swipe, or vertical
/// swipe-down based on displacement between touch-down and touch-up positions.
///
/// A displacement greater than [swipeThreshold] (10% of screen dimension by
/// default) is classified as a swipe; otherwise it's a tap. When both axes
/// exceed the threshold, the dominant axis wins.
GestureType classifyGesture({
  required double downX,
  required double upX,
  double? downY,
  double? upY,
  double swipeThreshold = kSwipeDistanceThreshold,
}) {
  final dx = (upX - downX).abs();
  final dy = (downY != null && upY != null) ? (upY - downY).abs() : 0.0;
  final hasVertical = downY != null && upY != null;
  final isDownward = hasVertical && upY > downY;
  final isUpward = hasVertical && upY < downY;

  if (dx <= swipeThreshold && dy <= swipeThreshold) {
    return GestureType.tap;
  }

  // Vertical swipe takes priority when dominant.
  if (dy > dx && isDownward) {
    return GestureType.verticalSwipeDown;
  }
  if (dy > dx && isUpward) {
    return GestureType.verticalSwipeUp;
  }

  if (dx > swipeThreshold) {
    return GestureType.horizontalSwipe;
  }

  return GestureType.tap;
}

/// Resolves a raw-pixel e-reader-mode pointer gesture into a navigation
/// intent.
///
/// [classifyGesture] and [resolveSwipeIntent]'s thresholds are fractions of a
/// screen dimension, so the pixel deltas are normalized by [screenWidth] /
/// [screenHeight] before classification. Anything that isn't a clean
/// horizontal swipe resolves to [ReaderNavigationIntent.none].
ReaderNavigationIntent resolveEreaderSwipeIntent({
  required double downX,
  required double upX,
  required double downY,
  required double upY,
  required double screenWidth,
  required double screenHeight,
  required ReaderDirection readingDirection,
}) {
  if (screenWidth <= 0 || screenHeight <= 0) {
    return ReaderNavigationIntent.none;
  }

  final gesture = classifyGesture(
    downX: downX / screenWidth,
    upX: upX / screenWidth,
    downY: downY / screenHeight,
    upY: upY / screenHeight,
  );
  if (gesture != GestureType.horizontalSwipe) {
    return ReaderNavigationIntent.none;
  }

  return intentForHorizontalSwipe(
    towardRight: upX > downX,
    readingDirection: readingDirection,
  );
}

// ── Section-aware navigation ────────────────────────────────────────

/// Navigation actions resolved from page position within a section.
///
/// These mirror the decision logic in reader_bridge.js next()/previous()
/// to allow unit-testing the section-boundary navigation that prevents
/// the epub.js page-skipping bug.
enum SectionNavigationAction {
  scrollWithinSection,
  jumpToNextSection,
  jumpToPreviousSection,
  alreadyAtEnd,
  alreadyAtStart,
}

/// Determines the correct forward-navigation action given current page
/// position within a section.
///
/// If the current page is before the last page, the caller should scroll
/// within the section. If on the last page, the caller should jump directly
/// to the next section (bypassing epub.js's broken delta-comparison logic).
SectionNavigationAction resolveNextAction({
  required int currentPage,
  required int totalPages,
  required bool hasNextSection,
}) {
  if (currentPage < totalPages) {
    return SectionNavigationAction.scrollWithinSection;
  }
  return hasNextSection
      ? SectionNavigationAction.jumpToNextSection
      : SectionNavigationAction.alreadyAtEnd;
}

/// Determines the correct backward-navigation action given current page
/// position within a section.
///
/// If the current page is after the first page, the caller should scroll
/// within the section. If on the first page, the caller should jump directly
/// to the previous section.
SectionNavigationAction resolvePreviousAction({
  required int currentPage,
  required int totalPages,
  required bool hasPreviousSection,
}) {
  if (currentPage > 1) {
    return SectionNavigationAction.scrollWithinSection;
  }
  return hasPreviousSection
      ? SectionNavigationAction.jumpToPreviousSection
      : SectionNavigationAction.alreadyAtStart;
}

// ── Page transition inference ───────────────────────────────────────

PageTransitionDirection inferPageTransitionDirection({
  required double previousProgress,
  required double currentProgress,
  double tolerance = 0.0001,
}) {
  final delta = currentProgress - previousProgress;
  if (delta.abs() <= tolerance) {
    return PageTransitionDirection.none;
  }

  return delta > 0
      ? PageTransitionDirection.forward
      : PageTransitionDirection.backward;
}
