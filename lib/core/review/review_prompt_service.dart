import 'package:in_app_review/in_app_review.dart';
import 'package:mekuru/core/review/review_prompt_policy.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

/// Requests a Play in-app review after a qualifying reading session.
///
/// Call [maybeRequestReview] fire-and-forget when the user returns to the
/// library. It never throws and never blocks the caller; whether a dialog is
/// actually shown remains at the discretion of the Play quota.
class ReviewPromptService {
  ReviewPromptService({
    required ReviewPromptStorage storage,
    required Future<int> Function() countSavedWords,
    InAppReview? inAppReview,
    DateTime Function()? clock,
  }) : _storage = storage,
       _countSavedWords = countSavedWords,
       _inAppReview = inAppReview ?? InAppReview.instance,
       _clock = clock ?? DateTime.now;

  final ReviewPromptStorage _storage;
  final Future<int> Function() _countSavedWords;
  final InAppReview _inAppReview;
  final DateTime Function() _clock;

  Future<void> maybeRequestReview({required DateTime sessionStartedAt}) async {
    try {
      final now = _clock();
      final state = await _storage.load();
      if (state.firstSeenAt == null) {
        // Start the usage-age clock; never prompt on the visit that starts it.
        await _storage.saveFirstSeenAt(now);
        return;
      }
      // Cheap prefs/clock gates first; the DB count only runs when a prompt
      // is still possible.
      final passesUsageGates = ReviewPromptPolicy.passesUsageGates(
        now: now,
        firstSeenAt: state.firstSeenAt,
        sessionDuration: now.difference(sessionStartedAt),
        requestCount: state.requestCount,
        lastRequestAt: state.lastRequestAt,
      );
      if (!passesUsageGates) return;
      final savedWordCount = await _countSavedWords();
      if (savedWordCount < ReviewPromptPolicy.minSavedWords) return;
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
