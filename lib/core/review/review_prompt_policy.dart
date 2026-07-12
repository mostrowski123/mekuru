/// Gating rules for the Play in-app review prompt.
///
/// Pure Dart — no Flutter imports — so the rules stay unit-testable.
/// Deliberately conservative: the prompt only fires after the user has
/// demonstrably gotten value from the app and just finished a real reading
/// session, and it can only ever fire a handful of times.
class ReviewPromptPolicy {
  /// Saved vocabulary proves the core loop delivered value.
  static const int minSavedWords = 15;

  /// Never prompt users who picked the app up less than a week ago.
  static const Duration minUsageAge = Duration(days: 7);

  /// Only prompt after a substantial reading session, not a quick open-close.
  static const Duration minSessionDuration = Duration(minutes: 5);

  /// The Play API gives no signal whether a dialog was actually shown, so a
  /// few widely spaced attempts are allowed instead of a single shot.
  static const int maxRequests = 3;
  static const Duration requestCooldown = Duration(days: 60);

  /// The gates that need no database access. The service checks these first
  /// so the saved-word count query only runs when a prompt is still possible.
  static bool passesUsageGates({
    required DateTime now,
    required DateTime? firstSeenAt,
    required Duration sessionDuration,
    required int requestCount,
    required DateTime? lastRequestAt,
  }) {
    if (firstSeenAt == null || now.difference(firstSeenAt) < minUsageAge) {
      return false;
    }
    if (sessionDuration < minSessionDuration) return false;
    if (requestCount >= maxRequests) return false;
    if (lastRequestAt != null &&
        now.difference(lastRequestAt) < requestCooldown) {
      return false;
    }
    return true;
  }

  static bool shouldRequestReview({
    required DateTime now,
    required DateTime? firstSeenAt,
    required int savedWordCount,
    required Duration sessionDuration,
    required int requestCount,
    required DateTime? lastRequestAt,
  }) {
    if (savedWordCount < minSavedWords) return false;
    return passesUsageGates(
      now: now,
      firstSeenAt: firstSeenAt,
      sessionDuration: sessionDuration,
      requestCount: requestCount,
      lastRequestAt: lastRequestAt,
    );
  }
}
