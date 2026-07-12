import 'package:shared_preferences/shared_preferences.dart';

/// Persisted state for the in-app review prompt.
class ReviewPromptState {
  const ReviewPromptState({
    this.firstSeenAt,
    this.requestCount = 0,
    this.lastRequestAt,
  });

  final DateTime? firstSeenAt;
  final int requestCount;
  final DateTime? lastRequestAt;
}

abstract class ReviewPromptStorage {
  Future<ReviewPromptState> load();
  Future<void> saveFirstSeenAt(DateTime value);
  Future<void> recordRequest(DateTime requestedAt, int newCount);
}

class SharedPreferencesReviewPromptStorage implements ReviewPromptStorage {
  static const _firstSeenAtKey = 'review_prompt.first_seen_at';
  static const _requestCountKey = 'review_prompt.request_count';
  static const _lastRequestAtKey = 'review_prompt.last_request_at';

  @override
  Future<ReviewPromptState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReviewPromptState(
      firstSeenAt: _parseInstant(prefs.getString(_firstSeenAtKey)),
      requestCount: prefs.getInt(_requestCountKey) ?? 0,
      lastRequestAt: _parseInstant(prefs.getString(_lastRequestAtKey)),
    );
  }

  @override
  Future<void> saveFirstSeenAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_firstSeenAtKey, value.toIso8601String());
  }

  @override
  Future<void> recordRequest(DateTime requestedAt, int newCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_requestCountKey, newCount);
    await prefs.setString(_lastRequestAtKey, requestedAt.toIso8601String());
  }

  static DateTime? _parseInstant(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso);
}
