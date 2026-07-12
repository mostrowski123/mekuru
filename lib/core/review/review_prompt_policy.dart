/// Gating rules for the Play in-app review prompt.
///
/// Pure Dart — no Flutter imports — so the rules stay unit-testable.
/// Deliberately conservative: the prompt only fires for users with a real
/// reading habit, never at launch or mid-session, and only a handful of
/// times ever.
class ReviewPromptPolicy {
  /// Repeated substantial sessions prove the reading loop delivered value —
  /// unlike saved-word counts, this holds for users who send words straight
  /// to Anki instead of saving them.
  static const int minQualifyingSessions = 5;

  /// Never prompt users who picked the app up less than a week ago.
  static const Duration minUsageAge = Duration(days: 7);

  /// Only sessions this long count as qualifying — filters quick open-close.
  static const Duration minSessionDuration = Duration(minutes: 5);

  /// The Play API gives no signal whether a dialog was actually shown, so a
  /// few widely spaced attempts are allowed instead of a single shot.
  static const int maxRequests = 3;
  static const Duration requestCooldown = Duration(days: 60);

  static bool isQualifyingSession(Duration sessionDuration) =>
      sessionDuration >= minSessionDuration;

  static bool shouldRequestReview({
    required DateTime now,
    required DateTime? firstSeenAt,
    required int qualifyingSessions,
    required int requestCount,
    required DateTime? lastRequestAt,
  }) {
    if (qualifyingSessions < minQualifyingSessions) return false;
    if (firstSeenAt == null || now.difference(firstSeenAt) < minUsageAge) {
      return false;
    }
    if (requestCount >= maxRequests) return false;
    if (lastRequestAt != null &&
        now.difference(lastRequestAt) < requestCooldown) {
      return false;
    }
    return true;
  }
}
