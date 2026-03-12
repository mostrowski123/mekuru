import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';

void main() {
  // ── isCenterTapZone ─────────────────────────────────────────────────

  group('isCenterTapZone', () {
    test('returns true for tap in center of screen', () {
      expect(isCenterTapZone(x: 0.5), isTrue);
    });

    test('returns true at left boundary of zone', () {
      // Zone starts at (1.0 - 0.5) / 2 = 0.25
      expect(isCenterTapZone(x: 0.25), isTrue);
    });

    test('returns true at right boundary of zone', () {
      // Zone ends at 0.25 + 0.50 = 0.75
      expect(isCenterTapZone(x: 0.75), isTrue);
    });

    test('returns false just outside left boundary', () {
      expect(isCenterTapZone(x: 0.24), isFalse);
    });

    test('returns false just outside right boundary', () {
      expect(isCenterTapZone(x: 0.76), isFalse);
    });

    test('returns false for x at far left', () {
      expect(isCenterTapZone(x: 0.1), isFalse);
    });

    test('returns false for x at far right', () {
      expect(isCenterTapZone(x: 0.9), isFalse);
    });

    test('respects custom widthFraction', () {
      // With widthFraction=0.6: zone is [0.2, 0.8]
      expect(isCenterTapZone(x: 0.5, widthFraction: 0.6), isTrue);
      expect(isCenterTapZone(x: 0.19, widthFraction: 0.6), isFalse);
      expect(isCenterTapZone(x: 0.81, widthFraction: 0.6), isFalse);
    });
  });

  group('mangaCenterTapZoneWidthFromEdgeZoneWidth', () {
    test('uses a thinner default manga edge zone', () {
      expect(
        mangaCenterTapZoneWidthFromEdgeZoneWidth(
          kDefaultMangaPageTurnEdgeZoneWidthFraction,
        ),
        0.7,
      );
    });

    test('clamps values outside the supported range', () {
      expect(mangaCenterTapZoneWidthFromEdgeZoneWidth(0.0), 0.9);
      expect(mangaCenterTapZoneWidthFromEdgeZoneWidth(0.5), 0.5);
    });
  });

  // ── inferPageTransitionDirection ──────────────────────────────────────

  group('inferPageTransitionDirection', () {
    test('returns forward when progress increases', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.2,
        currentProgress: 0.5,
      );
      expect(direction, PageTransitionDirection.forward);
    });

    test('returns backward when progress decreases', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.7,
        currentProgress: 0.3,
      );
      expect(direction, PageTransitionDirection.backward);
    });

    test('returns none when progress change is within tolerance', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.4,
        currentProgress: 0.40005,
      );
      expect(direction, PageTransitionDirection.none);
    });

    test('returns none when progress is exactly the same', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.5,
        currentProgress: 0.5,
      );
      expect(direction, PageTransitionDirection.none);
    });

    test('returns forward for exactly at tolerance boundary', () {
      // Default tolerance is 0.0001, so a delta of 0.00011 should be forward
      final direction = inferPageTransitionDirection(
        previousProgress: 0.5,
        currentProgress: 0.50011,
      );
      expect(direction, PageTransitionDirection.forward);
    });

    test('returns none for delta exactly at tolerance', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.5,
        currentProgress: 0.5001,
      );
      expect(direction, PageTransitionDirection.none);
    });

    test('returns forward for large jump 0.0 to 1.0', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 0.0,
        currentProgress: 1.0,
      );
      expect(direction, PageTransitionDirection.forward);
    });

    test('returns backward for large jump 1.0 to 0.0', () {
      final direction = inferPageTransitionDirection(
        previousProgress: 1.0,
        currentProgress: 0.0,
      );
      expect(direction, PageTransitionDirection.backward);
    });
  });

  // ── resolveTapIntent ──────────────────────────────────────────────────

  group('resolveTapIntent', () {
    test('returns toggleControls in center zone', () {
      final intent = resolveTapIntent(
        normalizedX: 0.5,
        normalizedY: 0.05,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.toggleControls);
    });

    test('returns toggleControls for center of screen', () {
      // Center of screen (y=0.5) is now in the toggle zone
      final intent = resolveTapIntent(
        normalizedX: 0.5,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.toggleControls);
    });

    test('returns toggleControls at bottom center', () {
      final intent = resolveTapIntent(
        normalizedX: 0.5,
        normalizedY: 0.95,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.toggleControls);
    });

    test('maps edge taps correctly for rtl', () {
      final leftIntent = resolveTapIntent(
        normalizedX: 0.1,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
      );
      final rightIntent = resolveTapIntent(
        normalizedX: 0.9,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
      );

      expect(leftIntent, ReaderNavigationIntent.goForward);
      expect(rightIntent, ReaderNavigationIntent.goBackward);
    });

    test('maps edge taps correctly for ltr', () {
      final leftIntent = resolveTapIntent(
        normalizedX: 0.1,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.ltr,
      );
      final rightIntent = resolveTapIntent(
        normalizedX: 0.9,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.ltr,
      );

      expect(leftIntent, ReaderNavigationIntent.goBackward);
      expect(rightIntent, ReaderNavigationIntent.goForward);
    });

    test('tap at x = 0.0 is left edge for rtl (goForward)', () {
      final intent = resolveTapIntent(
        normalizedX: 0.0,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.goForward);
    });

    test('tap at x = 1.0 is right edge for rtl (goBackward)', () {
      final intent = resolveTapIntent(
        normalizedX: 1.0,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.goBackward);
    });

    test('tap at x = 0.0 is left edge for ltr (goBackward)', () {
      final intent = resolveTapIntent(
        normalizedX: 0.0,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.ltr,
      );
      expect(intent, ReaderNavigationIntent.goBackward);
    });

    test('tap at x = 1.0 is right edge for ltr (goForward)', () {
      final intent = resolveTapIntent(
        normalizedX: 1.0,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.ltr,
      );
      expect(intent, ReaderNavigationIntent.goForward);
    });

    test('tap at top-left (outside center zone) navigates', () {
      final intent = resolveTapIntent(
        normalizedX: 0.1,
        normalizedY: 0.05,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.goForward);
    });

    test('tap at top-right (outside center zone) navigates', () {
      final intent = resolveTapIntent(
        normalizedX: 0.9,
        normalizedY: 0.05,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.goBackward);
    });

    test('supports thinner manga edge zones near the device edge', () {
      final nearEdgeIntent = resolveTapIntent(
        normalizedX: 0.14,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
        centerZoneWidthFraction: mangaCenterTapZoneWidthFromEdgeZoneWidth(
          kDefaultMangaPageTurnEdgeZoneWidthFraction,
        ),
      );
      final innerIntent = resolveTapIntent(
        normalizedX: 0.16,
        normalizedY: 0.5,
        readingDirection: ReaderDirection.rtl,
        centerZoneWidthFraction: mangaCenterTapZoneWidthFromEdgeZoneWidth(
          kDefaultMangaPageTurnEdgeZoneWidthFraction,
        ),
      );

      expect(nearEdgeIntent, ReaderNavigationIntent.goForward);
      expect(innerIntent, ReaderNavigationIntent.toggleControls);
    });
  });

  // ── resolveSwipeIntent ────────────────────────────────────────────────

  group('resolveSwipeIntent', () {
    test('returns none for small velocity', () {
      final intent = resolveSwipeIntent(
        velocityX: 100,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.none);
    });

    test('maps swipe directions for rtl', () {
      final rightSwipeIntent = resolveSwipeIntent(
        velocityX: 500,
        readingDirection: ReaderDirection.rtl,
      );
      final leftSwipeIntent = resolveSwipeIntent(
        velocityX: -500,
        readingDirection: ReaderDirection.rtl,
      );

      expect(rightSwipeIntent, ReaderNavigationIntent.goForward);
      expect(leftSwipeIntent, ReaderNavigationIntent.goBackward);
    });

    test('maps swipe directions for ltr', () {
      final rightSwipeIntent = resolveSwipeIntent(
        velocityX: 500,
        readingDirection: ReaderDirection.ltr,
      );
      final leftSwipeIntent = resolveSwipeIntent(
        velocityX: -500,
        readingDirection: ReaderDirection.ltr,
      );

      expect(rightSwipeIntent, ReaderNavigationIntent.goBackward);
      expect(leftSwipeIntent, ReaderNavigationIntent.goForward);
    });

    test('returns none for velocity exactly at threshold (400.0)', () {
      final intent = resolveSwipeIntent(
        velocityX: 400.0,
        readingDirection: ReaderDirection.rtl,
      );
      // abs(400.0) < 400.0 is false, so it should navigate
      expect(intent, ReaderNavigationIntent.goForward);
    });

    test('returns none for velocity just below threshold (399.9)', () {
      final intent = resolveSwipeIntent(
        velocityX: 399.9,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.none);
    });

    test('returns none for zero velocity', () {
      final intent = resolveSwipeIntent(
        velocityX: 0.0,
        readingDirection: ReaderDirection.rtl,
      );
      expect(intent, ReaderNavigationIntent.none);
    });

    test('returns none for negative velocity below threshold', () {
      final intent = resolveSwipeIntent(
        velocityX: -200.0,
        readingDirection: ReaderDirection.ltr,
      );
      expect(intent, ReaderNavigationIntent.none);
    });
  });

  // ── classifyGesture ───────────────────────────────────────────────────

  group('classifyGesture', () {
    test('small displacement returns tap', () {
      expect(classifyGesture(downX: 0.5, upX: 0.55), GestureType.tap);
    });

    test('large horizontal displacement returns horizontalSwipe', () {
      expect(
        classifyGesture(downX: 0.3, upX: 0.5),
        GestureType.horizontalSwipe,
      );
    });

    test('exactly at threshold returns tap (not strictly greater)', () {
      // 0.6 - 0.5 = 0.1, which is NOT > 0.1, so it's a tap
      expect(classifyGesture(downX: 0.5, upX: 0.6), GestureType.tap);
    });

    test('just above threshold returns horizontalSwipe', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.6001),
        GestureType.horizontalSwipe,
      );
    });

    test('negative displacement (swipe left) returns horizontalSwipe', () {
      expect(
        classifyGesture(downX: 0.8, upX: 0.5),
        GestureType.horizontalSwipe,
      );
    });

    test('zero displacement returns tap', () {
      expect(classifyGesture(downX: 0.5, upX: 0.5), GestureType.tap);
    });

    test('maximum displacement (0 to 1) returns horizontalSwipe', () {
      expect(
        classifyGesture(downX: 0.0, upX: 1.0),
        GestureType.horizontalSwipe,
      );
    });

    test('maximum negative displacement (1 to 0) returns horizontalSwipe', () {
      expect(
        classifyGesture(downX: 1.0, upX: 0.0),
        GestureType.horizontalSwipe,
      );
    });

    test('custom threshold is respected', () {
      // With threshold 0.05, a 0.06 displacement is a swipe
      expect(
        classifyGesture(downX: 0.5, upX: 0.56, swipeThreshold: 0.05),
        GestureType.horizontalSwipe,
      );
      // But 0.04 displacement is a tap
      expect(
        classifyGesture(downX: 0.5, upX: 0.54, swipeThreshold: 0.05),
        GestureType.tap,
      );
    });

    test('vertical swipe down detected when Y displacement dominates', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.5, downY: 0.2, upY: 0.5),
        GestureType.verticalSwipeDown,
      );
    });

    test('vertical swipe up detected when Y displacement dominates upward', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.5, downY: 0.5, upY: 0.2),
        GestureType.verticalSwipeUp,
      );
    });

    test('horizontal swipe wins when dx > dy', () {
      expect(
        classifyGesture(downX: 0.2, upX: 0.6, downY: 0.5, upY: 0.6),
        GestureType.horizontalSwipe,
      );
    });

    test('vertical swipe down wins when dy > dx and downward', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.55, downY: 0.3, upY: 0.6),
        GestureType.verticalSwipeDown,
      );
    });

    test('vertical swipe up wins when dy > dx and upward', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.55, downY: 0.6, upY: 0.3),
        GestureType.verticalSwipeUp,
      );
    });

    test('no Y data falls back to horizontal-only classification', () {
      expect(
        classifyGesture(downX: 0.3, upX: 0.5),
        GestureType.horizontalSwipe,
      );
      expect(classifyGesture(downX: 0.5, upX: 0.55), GestureType.tap);
    });

    test('small vertical and horizontal displacement is a tap', () {
      expect(
        classifyGesture(downX: 0.5, upX: 0.55, downY: 0.5, upY: 0.55),
        GestureType.tap,
      );
    });
  });

  // ── resolveNextAction ─────────────────────────────────────────────────

  group('resolveNextAction', () {
    test('mid-section: page 1/5 scrolls within section', () {
      expect(
        resolveNextAction(currentPage: 1, totalPages: 5, hasNextSection: true),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test('mid-section: page 3/5 scrolls within section', () {
      expect(
        resolveNextAction(currentPage: 3, totalPages: 5, hasNextSection: true),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test('last page with next section: page 5/5 jumps to next section', () {
      expect(
        resolveNextAction(currentPage: 5, totalPages: 5, hasNextSection: true),
        SectionNavigationAction.jumpToNextSection,
      );
    });

    test('last page without next section: page 5/5 at end of book', () {
      expect(
        resolveNextAction(currentPage: 5, totalPages: 5, hasNextSection: false),
        SectionNavigationAction.alreadyAtEnd,
      );
    });

    test('single-page section with next: page 1/1 jumps to next section '
        '(THE BUG CASE — epub.js would skip this)', () {
      expect(
        resolveNextAction(currentPage: 1, totalPages: 1, hasNextSection: true),
        SectionNavigationAction.jumpToNextSection,
      );
    });

    test('single-page section without next: page 1/1 at end of book', () {
      expect(
        resolveNextAction(currentPage: 1, totalPages: 1, hasNextSection: false),
        SectionNavigationAction.alreadyAtEnd,
      );
    });

    test('second-to-last page scrolls within section', () {
      expect(
        resolveNextAction(currentPage: 4, totalPages: 5, hasNextSection: true),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test('last page of last section with no next is alreadyAtEnd', () {
      expect(
        resolveNextAction(
          currentPage: 10,
          totalPages: 10,
          hasNextSection: false,
        ),
        SectionNavigationAction.alreadyAtEnd,
      );
    });
  });

  // ── resolvePreviousAction ─────────────────────────────────────────────

  group('resolvePreviousAction', () {
    test('mid-section: page 3/5 scrolls within section', () {
      expect(
        resolvePreviousAction(
          currentPage: 3,
          totalPages: 5,
          hasPreviousSection: true,
        ),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test('mid-section: page 5/5 scrolls within section', () {
      expect(
        resolvePreviousAction(
          currentPage: 5,
          totalPages: 5,
          hasPreviousSection: true,
        ),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test(
      'first page with prev section: page 1/5 jumps to previous section',
      () {
        expect(
          resolvePreviousAction(
            currentPage: 1,
            totalPages: 5,
            hasPreviousSection: true,
          ),
          SectionNavigationAction.jumpToPreviousSection,
        );
      },
    );

    test('first page without prev section: page 1/5 at start of book', () {
      expect(
        resolvePreviousAction(
          currentPage: 1,
          totalPages: 5,
          hasPreviousSection: false,
        ),
        SectionNavigationAction.alreadyAtStart,
      );
    });

    test('single-page section with prev: page 1/1 jumps to previous section '
        '(THE BUG CASE — epub.js would skip this)', () {
      expect(
        resolvePreviousAction(
          currentPage: 1,
          totalPages: 1,
          hasPreviousSection: true,
        ),
        SectionNavigationAction.jumpToPreviousSection,
      );
    });

    test('single-page section without prev: page 1/1 at start of book', () {
      expect(
        resolvePreviousAction(
          currentPage: 1,
          totalPages: 1,
          hasPreviousSection: false,
        ),
        SectionNavigationAction.alreadyAtStart,
      );
    });

    test('second page scrolls within section', () {
      expect(
        resolvePreviousAction(
          currentPage: 2,
          totalPages: 5,
          hasPreviousSection: true,
        ),
        SectionNavigationAction.scrollWithinSection,
      );
    });

    test('first page of first section with no prev is alreadyAtStart', () {
      expect(
        resolvePreviousAction(
          currentPage: 1,
          totalPages: 10,
          hasPreviousSection: false,
        ),
        SectionNavigationAction.alreadyAtStart,
      );
    });
  });
}
