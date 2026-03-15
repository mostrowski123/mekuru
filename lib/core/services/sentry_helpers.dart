import 'package:sentry_flutter/sentry_flutter.dart';

/// Runs [action] and records its duration as a Sentry distribution metric.
Future<T> tracedOperation<T>(
  String metricName, {
  required Future<T> Function() action,
  Map<String, SentryAttribute>? attributes,
}) async {
  final sw = Stopwatch()..start();
  try {
    final result = await action();
    sw.stop();
    Sentry.metrics.distribution(
      metricName,
      sw.elapsedMilliseconds,
      unit: SentryMetricUnit.millisecond,
      attributes: attributes,
    );
    return result;
  } catch (e) {
    sw.stop();
    Sentry.metrics.distribution(
      metricName,
      sw.elapsedMilliseconds,
      unit: SentryMetricUnit.millisecond,
      attributes: {
        ...?attributes,
        'error': SentryAttribute.bool(true),
      },
    );
    rethrow;
  }
}
