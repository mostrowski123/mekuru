import 'package:in_app_review/in_app_review.dart';
import 'package:mekuru/core/review/review_prompt_policy.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

/// Requests a Play in-app review after a qualifying reading session.
///
/// Call [maybeRequestReview] fire-and-forget when a reader screen closes. It
/// never throws and never blocks the caller; whether a dialog is actually
/// shown remains at the discretion of the Play quota.
class ReviewPromptService {
  ReviewPromptService({
    required ReviewPromptStorage storage,
    bool Function()? isSafeToPrompt,
    InAppReview? inAppReview,
    DateTime Function()? clock,
  }) : _storage = storage,
       _isSafeToPrompt = isSafeToPrompt ?? (() => true),
       _inAppReview = inAppReview ?? InAppReview.instance,
       _clock = clock ?? DateTime.now;

  final ReviewPromptStorage _storage;

  /// Last-moment veto — e.g. the user already opened another reader, so the
  /// dialog would land on top of a reading session.
  final bool Function() _isSafeToPrompt;
  final InAppReview _inAppReview;
  final DateTime Function() _clock;

  Future<void> maybeRequestReview({required DateTime sessionStartedAt}) async {
    try {
      final now = _clock();
      final state = await _storage.load();
      if (state.firstSeenAt == null) {
        // Start the usage-age clock on the first session ever seen.
        await _storage.saveFirstSeenAt(now);
      }
      if (!ReviewPromptPolicy.isQualifyingSession(
        now.difference(sessionStartedAt),
      )) {
        return;
      }
      final qualifyingSessions = state.qualifyingSessions + 1;
      await _storage.saveQualifyingSessions(qualifyingSessions);
      final shouldRequest = ReviewPromptPolicy.shouldRequestReview(
        now: now,
        firstSeenAt: state.firstSeenAt,
        qualifyingSessions: qualifyingSessions,
        requestCount: state.requestCount,
        lastRequestAt: state.lastRequestAt,
      );
      if (!shouldRequest) return;
      if (!_isSafeToPrompt()) return;
      if (!await _inAppReview.isAvailable()) return;
      // Record before requesting so a failure can never cause re-prompting.
      final newCount = state.requestCount + 1;
      await _storage.recordRequest(now, newCount);
      logUsage('review_prompt.requested', attrs: {'request_count': newCount});
      await _inAppReview.requestReview();
    } catch (_) {
      // The review prompt must never surface an error to the user.
    }
  }
}
