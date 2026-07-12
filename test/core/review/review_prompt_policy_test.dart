import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/review/review_prompt_policy.dart';

void main() {
  final now = DateTime(2026, 7, 12, 20);

  /// Baseline arguments that satisfy every gate; each test flips one.
  bool decide({
    DateTime? firstSeenAt,
    int qualifyingSessions = 6,
    int requestCount = 0,
    DateTime? lastRequestAt,
  }) {
    return ReviewPromptPolicy.shouldRequestReview(
      now: now,
      firstSeenAt: firstSeenAt ?? now.subtract(const Duration(days: 30)),
      qualifyingSessions: qualifyingSessions,
      requestCount: requestCount,
      lastRequestAt: lastRequestAt,
    );
  }

  group('isQualifyingSession', () {
    test('accepts sessions at or above the minimum duration', () {
      expect(
        ReviewPromptPolicy.isQualifyingSession(
          ReviewPromptPolicy.minSessionDuration,
        ),
        isTrue,
      );
      expect(
        ReviewPromptPolicy.isQualifyingSession(const Duration(minutes: 4)),
        isFalse,
      );
    });
  });

  group('shouldRequestReview', () {
    test('allows when every gate passes', () {
      expect(decide(), isTrue);
    });

    test('blocks below the qualifying-session threshold', () {
      expect(
        decide(
          qualifyingSessions: ReviewPromptPolicy.minQualifyingSessions - 1,
        ),
        isFalse,
      );
      expect(
        decide(qualifyingSessions: ReviewPromptPolicy.minQualifyingSessions),
        isTrue,
      );
    });

    test('blocks when first seen is unknown', () {
      expect(
        ReviewPromptPolicy.shouldRequestReview(
          now: now,
          firstSeenAt: null,
          qualifyingSessions: 6,
          requestCount: 0,
          lastRequestAt: null,
        ),
        isFalse,
      );
    });

    test('blocks users newer than the minimum usage age', () {
      expect(
        decide(firstSeenAt: now.subtract(const Duration(days: 6))),
        isFalse,
      );
      expect(
        decide(firstSeenAt: now.subtract(const Duration(days: 8))),
        isTrue,
      );
    });

    test('blocks after the lifetime request budget is spent', () {
      expect(decide(requestCount: ReviewPromptPolicy.maxRequests), isFalse);
    });

    test('blocks inside the cooldown window, allows after it', () {
      expect(
        decide(
          requestCount: 1,
          lastRequestAt: now.subtract(const Duration(days: 30)),
        ),
        isFalse,
      );
      expect(
        decide(
          requestCount: 1,
          lastRequestAt: now.subtract(const Duration(days: 61)),
        ),
        isTrue,
      );
    });
  });
}
