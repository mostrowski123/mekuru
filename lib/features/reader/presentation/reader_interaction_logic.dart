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

ReaderNavigationIntent resolveTapIntent({
  required double normalizedX,
  required double normalizedY,
  required ReaderDirection readingDirection,
}) {
  if (isCenterTapZone(x: normalizedX)) {
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

  final isSwipeRight = velocityX > 0;
  if (isSwipeRight) {
    return readingDirection == ReaderDirection.rtl
        ? ReaderNavigationIntent.goForward
        : ReaderNavigationIntent.goBackward;
  }

  return readingDirection == ReaderDirection.rtl
      ? ReaderNavigationIntent.goBackward
      : ReaderNavigationIntent.goForward;
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
