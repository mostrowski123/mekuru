import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mekuru/core/review/review_prompt_service.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';

class _MemoryStorage implements ReviewPromptStorage {
  DateTime? firstSeenAt;
  int qualifyingSessions = 0;
  int requestCount = 0;
  DateTime? lastRequestAt;
  bool throwOnLoad = false;

  @override
  Future<ReviewPromptState> load() async {
    if (throwOnLoad) throw StateError('prefs unavailable');
    return ReviewPromptState(
      firstSeenAt: firstSeenAt,
      qualifyingSessions: qualifyingSessions,
      requestCount: requestCount,
      lastRequestAt: lastRequestAt,
    );
  }

  @override
  Future<void> saveFirstSeenAt(DateTime value) async => firstSeenAt = value;

  @override
  Future<void> saveQualifyingSessions(int count) async =>
      qualifyingSessions = count;

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
  final longSessionStart = now.subtract(const Duration(minutes: 10));

  _MemoryStorage eligibleStorage() => _MemoryStorage()
    ..firstSeenAt = now.subtract(const Duration(days: 30))
    ..qualifyingSessions = 4;

  ReviewPromptService buildService(
    _MemoryStorage storage,
    _FakeInAppReview review, {
    bool Function()? isSafeToPrompt,
  }) {
    return ReviewPromptService(
      storage: storage,
      isSafeToPrompt: isSafeToPrompt,
      inAppReview: review,
      clock: () => now,
    );
  }

  test('first session starts the usage-age clock and never prompts', () async {
    final storage = _MemoryStorage();
    final review = _FakeInAppReview();

    await buildService(
      storage,
      review,
    ).maybeRequestReview(sessionStartedAt: longSessionStart);

    expect(storage.firstSeenAt, now);
    expect(storage.qualifyingSessions, 1);
    expect(review.requestReviewCalls, 0);
  });

  test('short sessions are not counted and never prompt', () async {
    final storage = eligibleStorage();
    final review = _FakeInAppReview();

    await buildService(storage, review).maybeRequestReview(
      sessionStartedAt: now.subtract(const Duration(minutes: 1)),
    );

    expect(storage.qualifyingSessions, 4);
    expect(review.requestReviewCalls, 0);
  });

  test(
    'the qualifying session that crosses the threshold prompts and records',
    () async {
      final storage = eligibleStorage();
      final review = _FakeInAppReview();

      await buildService(
        storage,
        review,
      ).maybeRequestReview(sessionStartedAt: longSessionStart);

      expect(storage.qualifyingSessions, 5);
      expect(review.requestReviewCalls, 1);
      expect(storage.requestCount, 1);
      expect(storage.lastRequestAt, now);
    },
  );

  test('stays silent while another reader is open', () async {
    final storage = eligibleStorage();
    final review = _FakeInAppReview();

    await buildService(
      storage,
      review,
      isSafeToPrompt: () => false,
    ).maybeRequestReview(sessionStartedAt: longSessionStart);

    // The session still counts, but no attempt is made or burned.
    expect(storage.qualifyingSessions, 5);
    expect(review.requestReviewCalls, 0);
    expect(storage.requestCount, 0);
  });

  test('does not burn an attempt when the platform is unavailable', () async {
    final storage = eligibleStorage();
    final review = _FakeInAppReview(available: false);

    await buildService(
      storage,
      review,
    ).maybeRequestReview(sessionStartedAt: longSessionStart);

    expect(review.requestReviewCalls, 0);
    expect(storage.requestCount, 0);
  });

  test('swallows dependency errors', () async {
    final storage = eligibleStorage()..throwOnLoad = true;
    final review = _FakeInAppReview();

    await expectLater(
      buildService(
        storage,
        review,
      ).maybeRequestReview(sessionStartedAt: longSessionStart),
      completes,
    );
    expect(review.requestReviewCalls, 0);
  });
}
