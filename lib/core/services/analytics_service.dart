// ignore_for_file: discarded_futures
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_flavor.dart';

/// Thin wrapper around [FirebaseAnalytics] that reports only from installs
/// [configure] allowed, and silently drops events until Firebase is
/// initialized (lazy init pattern).
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;

  // Off until configured, so an isolate that never configures (the
  // WorkManager OCR worker, unit tests) reports nothing.
  bool _reports = false;
  String? _installSource;

  /// Decides at startup whether this install reports to Firebase Analytics,
  /// and the `install_source` it reports under.
  ///
  /// Only release builds the release workflows made ([kIsOfficialBuild]),
  /// on real devices, report. Gating here rather than at each call site also
  /// covers the automatic screen tracking from [navigatorObserver], and
  /// callers that reach for [logEvent] directly instead of going through
  /// `usage_telemetry.dart`.
  void configure({required bool isSynthetic, required String installSource}) {
    _reports = kReleaseMode && kIsOfficialBuild && !isSynthetic;
    _installSource = installSource;
  }

  /// Hands the [configure] decision to the native SDK, which also logs on
  /// its own (first_open, session_start, user_engagement).
  ///
  /// Writes `false` as well as `true`: the native SDK keeps the flag across
  /// launches, so it is written on every launch. Until it first runs, the
  /// native default (off, from AndroidManifest.xml and Info.plist) holds.
  Future<void> applyToFirebase() async {
    if (Firebase.apps.isEmpty) return;
    final analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(_reports);
    if (_reports) {
      await analytics.setUserProperty(
        name: 'install_source',
        value: _installSource,
      );
    }
  }

  FirebaseAnalytics? get _instance {
    if (!_reports) return null;
    if (_analytics != null) return _analytics;
    if (Firebase.apps.isEmpty) return null;
    _analytics = FirebaseAnalytics.instance;
    return _analytics;
  }

  /// Firebase Analytics navigator observer for automatic screen tracking.
  /// Returns null for an install that does not report, or if Firebase is not
  /// yet initialized.
  FirebaseAnalyticsObserver? get navigatorObserver {
    final analytics = _instance;
    if (analytics == null) return null;
    return FirebaseAnalyticsObserver(analytics: analytics);
  }

  void logEvent(String name, [Map<String, Object>? parameters]) {
    _instance?.logEvent(name: name, parameters: parameters);
  }

  /// Install-level segmentation (Firebase caps names at 24 chars and values
  /// at 36). Only enums and buckets — never identifiers.
  void setUserProperty(String name, String value) {
    _instance?.setUserProperty(name: name, value: value);
  }
}
