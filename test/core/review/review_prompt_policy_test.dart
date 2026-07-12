import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/review/review_prompt_policy.dart';

void main() {
  final now = DateTime(2026, 7, 12, 20);

  /// Baseline arguments that satisfy every gate; each test flips one.
  bool decide({
    DateTime? firstSeenAt,
    int savedWordCount = 20,
    Duration sessionDuration = const Duration(minutes: 10),
    int requestCount = 0,
    DateTime? lastRequestAt,
  }) {
    return ReviewPromptPolicy.shouldRequestReview(
      now: now,
      firstSeenAt: firstSeenAt ?? now.subtract(const Duration(days: 30)),
      savedWordCount: savedWordCount,
      sessionDuration: sessionDuration,
      requestCount: requestCount,
      lastRequestAt: lastRequestAt,
    );
  }

  group('shouldRequestReview', () {
    test('allows when every gate passes', () {
      expect(decide(), isTrue);
    });

    test('blocks below the saved-word threshold', () {
      expect(
        decide(savedWordCount: ReviewPromptPolicy.minSavedWords - 1),
        isFalse,
      );
      expect(decide(savedWordCount: ReviewPromptPolicy.minSavedWords), isTrue);
    });

    test('blocks when first seen is unknown', () {
      expect(
        ReviewPromptPolicy.shouldRequestReview(
          now: now,
          firstSeenAt: null,
          savedWordCount: 20,
          sessionDuration: const Duration(minutes: 10),
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

    test('blocks short reading sessions', () {
      expect(decide(sessionDuration: const Duration(minutes: 4)), isFalse);
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
