/// Fire-and-forget usage telemetry.
///
/// Every function here swallows all errors: telemetry must never crash the
/// app, block a caller, or alter control flow. Log messages are always the
/// constant event name — dynamic values go into attributes, which must only
/// carry non-personal data (enums, counts, durations, booleans, error types).
/// Never put book titles, file names, user text, or looked-up words in either.
library;

import 'dart:async';

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
@visibleForTesting
void resetUsageTagsForTest() {
  _usageTags.clear();
  _tagAttrs = const {};
}

/// Install segmentation set by [setUsageTag]; merged into every log, count
/// and duration attribute map so any dashboard can split by it. The Sentry
/// form is converted once per change, not once per page turn.
final Map<String, String> _usageTags = {};
Map<String, SentryAttribute> _tagAttrs = const {};

/// Sets a segmentation tag: a Sentry scope tag (so issues filter by it), a
/// Firebase user property, and an attribute on every subsequent usage log,
/// count and duration. Values must be enums or buckets — never counts,
/// identifiers, or anything a single install could be picked out by.
void setUsageTag(String key, String value) {
  _guarded(() {
    _usageTags[key] = value;
    _tagAttrs = _toSentryAttributes(_usageTags);
    Sentry.configureScope((scope) => scope.setTag(key, value));
    AnalyticsService.instance.setUserProperty(key, value);
  });
}

/// Buckets a library size so it can be a tag without becoming an identifier.
String librarySizeBucket(int books) => switch (books) {
  0 => '0',
  < 10 => '1-9',
  < 50 => '10-49',
  < 200 => '50-199',
  _ => '200+',
};

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
///
/// Pass [stackTrace] when the failure is a bug rather than an expected
/// condition: it also files a Sentry issue (stack, breadcrumbs, grouping,
/// alerting) so call sites never pair this with their own captureException.
void logFailure(
  String event,
  Object error, {
  StackTrace? stackTrace,
  Map<String, Object>? attrs,
}) {
  _guarded(() {
    _emitLog(event, {
      ...?attrs,
      'error_type': error.runtimeType.toString(),
      'error_message': sanitizeErrorText(error.toString()),
    }, isWarning: true);
    if (stackTrace != null) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
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
    sink(name, value, _taggedAttributes(attrs));
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
      attributes: _taggedAttributes(attrs),
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
    final collections = await countRows(db, db.collections);

    setUsageTag('pro', isPro.toString());
    setUsageTag('library_size', librarySizeBucket(books));

    Sentry.metrics.gauge('install.library_books', books);
    Sentry.metrics.gauge('install.dicts_enabled', enabledDicts);
    Sentry.metrics.gauge('install.saved_words', savedWords);
    Sentry.metrics.gauge('install.collections', collections);
    Sentry.metrics.gauge('install.is_pro', isPro ? 1 : 0);
    AnalyticsService.instance.logEvent('install_state', {
      'library_books': books,
      'dicts_enabled': enabledDicts,
      'saved_words': savedWords,
      'collections': collections,
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
  logSink(event, _taggedAttributes(attrs) ?? const {}, isWarning: isWarning);
  // The same trail rides on every crash report. Attribute values are enums,
  // counts and sanitized error text by contract, so there is nothing to scrub.
  Sentry.addBreadcrumb(
    Breadcrumb(
      message: event,
      category: 'usage',
      data: attrs,
      level: isWarning ? SentryLevel.warning : SentryLevel.info,
    ),
  );
  // Tags reach Firebase as user properties, so they are not repeated here.
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

/// Caller attributes layered over the install tags; null when both are empty
/// so metrics without attributes stay attribute-free.
Map<String, SentryAttribute>? _taggedAttributes(Map<String, Object>? attrs) {
  if (attrs == null) return _tagAttrs.isEmpty ? null : Map.of(_tagAttrs);
  return {..._tagAttrs, ..._toSentryAttributes(attrs)};
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
