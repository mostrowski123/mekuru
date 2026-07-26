import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thin wrapper around [FirebaseAnalytics] that silently drops events
/// if Firebase has not been initialized yet (lazy init pattern).
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  bool _suppressed = false;

  /// Stops this install from reporting anything to Firebase Analytics.
  ///
  /// Called once at startup for synthetic clients — emulators, cloud device
  /// farms, bots — whose activity would otherwise skew aggregate product
  /// metrics. Gating here rather than at each call site also covers the
  /// automatic screen tracking from [navigatorObserver], and callers that
  /// reach for [logEvent] directly instead of going through
  /// `usage_telemetry.dart`.
  void suppress() {
    _suppressed = true;
    _analytics = null;
  }

  FirebaseAnalytics? get _instance {
    if (_suppressed) return null;
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
