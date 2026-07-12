import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mekuru/core/review/review_prompt_service.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';

class _MemoryStorage implements ReviewPromptStorage {
  DateTime? firstSeenAt;
  int requestCount = 0;
  DateTime? lastRequestAt;

  @override
  Future<ReviewPromptState> load() async => ReviewPromptState(
    firstSeenAt: firstSeenAt,
    requestCount: requestCount,
    lastRequestAt: lastRequestAt,
  );

  @override
  Future<void> saveFirstSeenAt(DateTime value) async => firstSeenAt = value;

  @override
  Future<void> recordRequest(DateTime requestedAt, int newCount) async {
    requestCount = newCount;
    lastRequestAt = requestedAt;
  }
}

class _FakeInAppReview implements InAppReview {
  _FakeInAppReview({this.available = true});

  final bool available;
  int requestReviewCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requestReviewCalls++;

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async {}
}

void main() {
  final now = DateTime(2026, 7, 12, 20);
  final sessionStart = now.subtract(const Duration(minutes: 10));

  ReviewPromptService buildService(
    _MemoryStorage storage,
    _FakeInAppReview review, {
    Future<int> Function()? countSavedWords,
  }) {
    return ReviewPromptService(
      storage: storage,
      countSavedWords: countSavedWords ?? () async => 20,
      inAppReview: review,
      clock: () => now,
    );
  }

  test('first call only starts the usage-age clock, never prompts', () async {
    final storage = _MemoryStorage();
    final review = _FakeInAppReview();

    await buildService(
      storage,
      review,
    ).maybeRequestReview(sessionStartedAt: sessionStart);

    expect(storage.firstSeenAt, now);
    expect(review.requestReviewCalls, 0);
    expect(storage.requestCount, 0);
  });

  test(
    'qualifying session requests a review and records the attempt',
    () async {
      final storage = _MemoryStorage()
        ..firstSeenAt = now.subtract(const Duration(days: 30));
      final review = _FakeInAppReview();

      await buildService(
        storage,
        review,
      ).maybeRequestReview(sessionStartedAt: sessionStart);

      expect(review.requestReviewCalls, 1);
      expect(storage.requestCount, 1);
      expect(storage.lastRequestAt, now);
    },
  );

  test('does not burn an attempt when the platform is unavailable', () async {
    final storage = _MemoryStorage()
      ..firstSeenAt = now.subtract(const Duration(days: 30));
    final review = _FakeInAppReview(available: false);

    await buildService(
      storage,
      review,
    ).maybeRequestReview(sessionStartedAt: sessionStart);

    expect(review.requestReviewCalls, 0);
    expect(storage.requestCount, 0);
  });

  test('ineligible state stays silent', () async {
    final storage = _MemoryStorage()
      ..firstSeenAt = now.subtract(const Duration(days: 30));
    final review = _FakeInAppReview();

    await buildService(
      storage,
      review,
      countSavedWords: () async => 3,
    ).maybeRequestReview(sessionStartedAt: sessionStart);

    expect(review.requestReviewCalls, 0);
    expect(storage.requestCount, 0);
  });

  test(
    'skips the word-count query when the cheap gates already fail',
    () async {
      final storage = _MemoryStorage()
        ..firstSeenAt = now.subtract(const Duration(days: 30));
      final review = _FakeInAppReview();
      var countCalls = 0;

      await buildService(
        storage,
        review,
        countSavedWords: () async {
          countCalls++;
          return 100;
        },
      ).maybeRequestReview(
        // Too short a session — rejected before any database work.
        sessionStartedAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(countCalls, 0);
      expect(review.requestReviewCalls, 0);
    },
  );

  test('swallows dependency errors', () async {
    final storage = _MemoryStorage()
      ..firstSeenAt = now.subtract(const Duration(days: 30));
    final review = _FakeInAppReview();

    await expectLater(
      buildService(
        storage,
        review,
        countSavedWords: () async => throw StateError('db closed'),
      ).maybeRequestReview(sessionStartedAt: sessionStart),
      completes,
    );
    expect(review.requestReviewCalls, 0);
  });
}
