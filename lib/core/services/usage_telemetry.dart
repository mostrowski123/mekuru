/// Fire-and-forget usage telemetry.
///
/// Every function here swallows all errors: telemetry must never crash the
/// app, block a caller, or alter control flow. Log messages are always the
/// constant event name — dynamic values go into attributes, which must only
/// carry non-personal data (enums, counts, durations, booleans, error types).
/// Never put book titles, file names, user text, or looked-up words in either.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../database/database_provider.dart';
import '../database/row_count.dart';
import 'analytics_service.dart';
import 'pii_scrubber.dart';

typedef UsageLogSink =
    void Function(
      String message,
      Map<String, SentryAttribute> attributes, {
      required bool isWarning,
    });
typedef UsageCountSink =
    void Function(
      String name,
      int value,
      Map<String, SentryAttribute>? attributes,
    );
typedef UsageAnalyticsSink =
    void Function(String name, Map<String, Object>? parameters);

/// Test seams — production code must never set these.
@visibleForTesting
UsageLogSink? usageLogSinkOverride;
@visibleForTesting
UsageCountSink? usageCountSinkOverride;
@visibleForTesting
UsageAnalyticsSink? usageAnalyticsSinkOverride;

/// Logs one structured usage event to Sentry and mirrors it to Firebase
/// Analytics (`.` becomes `_` in the Analytics event name).
void logUsage(String event, {Map<String, Object>? attrs}) {
  _guarded(() {
    _emitLog(event, attrs, isWarning: false);
  });
}

/// Logs a failure event. The message stays the constant [event] name; the
/// error contributes its runtime type plus its text run through
/// [sanitizeErrorText], so failures are diagnosable without file paths or
/// document content leaving the device.
void logFailure(String event, Object error, {Map<String, Object>? attrs}) {
  _guarded(() {
    _emitLog(event, {
      ...?attrs,
      'error_type': error.runtimeType.toString(),
      'error_message': sanitizeErrorText(error.toString()),
    }, isWarning: true);
  });
}

/// Formats exception text for a telemetry attribute: keeps only the first
/// line (Dart parse errors append source snippets on later lines), redacts
/// user-identifying content via the shared [scrubPaths] battery, and caps at
/// 100 chars — Firebase Analytics truncates string parameters beyond that.
String sanitizeErrorText(String text) {
  final newline = text.indexOf('\n');
  var s = newline == -1 ? text : text.substring(0, newline);
  // Clamp before the regex passes: the input length is data-controlled and
  // only the first 100 chars survive anyway.
  if (s.length > 1000) s = s.substring(0, 1000);
  s = scrubPaths(s);
  return s.length > 100 ? '${s.substring(0, 99)}…' : s;
}

/// Increments a Sentry counter metric. Metrics-only (no Analytics fan-out) —
/// safe for high-frequency events like page turns and lookups, which the SDK
/// pre-aggregates before sending.
void countUsage(String name, {int value = 1, Map<String, Object>? attrs}) {
  _guarded(() {
    final sink = usageCountSinkOverride ?? _defaultCountSink;
    sink(name, value, attrs == null ? null : _toSentryAttributes(attrs));
  });
}

/// Records a duration as a Sentry distribution metric. Metrics-only.
void durationUsage(
  String name,
  int milliseconds, {
  Map<String, Object>? attrs,
}) {
  _guarded(() {
    Sentry.metrics.distribution(
      name,
      milliseconds,
      unit: SentryMetricUnit.millisecond,
      attributes: attrs == null ? null : _toSentryAttributes(attrs),
    );
  });
}

/// Emits once-per-launch "state of the install" gauges so aggregate dashboards
/// can answer what a typical install looks like (library size, dictionaries
/// enabled, vocabulary size, Pro share) without any per-user tracking.
Future<void> emitInstallGauges(AppDatabase db, {required bool isPro}) async {
  try {
    final books = await countRows(db, db.books);
    final enabledDicts = await countRows(
      db,
      db.dictionaryMetas,
      where: db.dictionaryMetas.isEnabled.equals(true),
    );
    final savedWords = await countRows(db, db.savedWords);

    Sentry.metrics.gauge('install.library_books', books);
    Sentry.metrics.gauge('install.dicts_enabled', enabledDicts);
    Sentry.metrics.gauge('install.saved_words', savedWords);
    Sentry.metrics.gauge('install.is_pro', isPro ? 1 : 0);
    AnalyticsService.instance.logEvent('install_state', {
      'library_books': books,
      'dicts_enabled': enabledDicts,
      'saved_words': savedWords,
      'is_pro': isPro ? 1 : 0,
    });
  } catch (error) {
    _swallow(error);
  }
}

void _emitLog(
  String event,
  Map<String, Object>? attrs, {
  required bool isWarning,
}) {
  final logSink = usageLogSinkOverride ?? _defaultLogSink;
  logSink(event, _toSentryAttributes(attrs ?? const {}), isWarning: isWarning);
  final analyticsSink = usageAnalyticsSinkOverride ?? _defaultAnalyticsSink;
  analyticsSink(
    event.replaceAll('.', '_'),
    attrs == null ? null : _toAnalyticsParams(attrs),
  );
}

void _defaultLogSink(
  String message,
  Map<String, SentryAttribute> attributes, {
  required bool isWarning,
}) {
  if (isWarning) {
    Sentry.logger.warn(message, attributes: attributes);
  } else {
    Sentry.logger.info(message, attributes: attributes);
  }
}

void _defaultCountSink(
  String name,
  int value,
  Map<String, SentryAttribute>? attributes,
) {
  Sentry.metrics.count(name, value, attributes: attributes);
}

void _defaultAnalyticsSink(String name, Map<String, Object>? parameters) {
  AnalyticsService.instance.logEvent(name, parameters);
}

void _guarded(void Function() action) {
  try {
    action();
  } catch (error) {
    _swallow(error);
  }
}

void _swallow(Object error) {
  assert(() {
    debugPrint('[UsageTelemetry] emit failed: ${error.runtimeType}');
    return true;
  }());
}

Map<String, SentryAttribute> _toSentryAttributes(Map<String, Object> attrs) {
  return attrs.map(
    (key, value) => MapEntry(key, switch (value) {
      final String v => SentryAttribute.string(v),
      final int v => SentryAttribute.int(v),
      final bool v => SentryAttribute.bool(v),
      final double v => SentryAttribute.double(v),
      _ => SentryAttribute.string(value.toString()),
    }),
  );
}

/// Firebase Analytics only accepts String and num parameter values.
Map<String, Object> _toAnalyticsParams(Map<String, Object> attrs) {
  return attrs.map(
    (key, value) => MapEntry(key, switch (value) {
      final num v => v,
      final String v => v,
      final bool v => v ? 1 : 0,
      _ => value.toString(),
    }),
  );
}
