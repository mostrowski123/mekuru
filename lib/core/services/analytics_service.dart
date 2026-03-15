import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thin wrapper around [FirebaseAnalytics] that silently drops events
/// if Firebase has not been initialized yet (lazy init pattern).
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;

  FirebaseAnalytics? get _instance {
    if (_analytics != null) return _analytics;
    if (Firebase.apps.isEmpty) return null;
    _analytics = FirebaseAnalytics.instance;
    return _analytics;
  }

  /// Firebase Analytics navigator observer for automatic screen tracking.
  /// Returns null if Firebase is not yet initialized.
  FirebaseAnalyticsObserver? get navigatorObserver {
    final analytics = _instance;
    if (analytics == null) return null;
    return FirebaseAnalyticsObserver(analytics: analytics);
  }

  void logEvent(String name, [Map<String, Object>? parameters]) {
    _instance?.logEvent(name: name, parameters: parameters);
  }
}
