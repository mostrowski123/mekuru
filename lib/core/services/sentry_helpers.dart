import 'usage_telemetry.dart';

const String _durationSuffix = '_duration_ms';

/// Runs [action], recording how long it took and — if it throws — reporting
/// the failure before rethrowing.
///
/// [metricName] follows the `<operation>_duration_ms` convention, and a
/// failure is reported as `<operation>_failed`. Putting this here rather than
/// at each call site means every traced operation gets a failure warning and
/// count for free: book imports, dictionary imports, and anything traced
/// later. Sentry held zero warning-severity logs across 90 days precisely
/// because each call site had to remember, and none did.
Future<T> tracedOperation<T>(
  String metricName, {
  required Future<T> Function() action,
  Map<String, Object>? attributes,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final result = await action();
    stopwatch.stop();
    durationUsage(metricName, stopwatch.elapsedMilliseconds, attrs: attributes);
    return result;
  } catch (error) {
    stopwatch.stop();
    durationUsage(
      metricName,
      stopwatch.elapsedMilliseconds,
      attrs: {...?attributes, 'error': true},
    );
    // Counting as well as logging keeps a failure *rate* derivable against the
    // operation's success counter.
    final failureEvent = '${_operationName(metricName)}_failed';
    logFailure(failureEvent, error, attrs: attributes);
    countUsage(failureEvent, attrs: attributes);
    rethrow;
  }
}

/// `book.import_duration_ms` -> `book.import`
String _operationName(String metricName) => metricName.endsWith(_durationSuffix)
    ? metricName.substring(0, metricName.length - _durationSuffix.length)
    : metricName;
