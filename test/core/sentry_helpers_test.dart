import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  late List<({String message, Map<String, SentryAttribute> attrs, bool warn})>
  logs;
  late List<({String name, Map<String, SentryAttribute>? attrs})> counts;

  setUp(() {
    logs = [];
    counts = [];
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message: message, attrs: attributes, warn: isWarning));
    usageCountSinkOverride = (name, value, attributes) =>
        counts.add((name: name, attrs: attributes));
    usageAnalyticsSinkOverride = (name, parameters) {};
  });

  tearDown(() {
    usageLogSinkOverride = null;
    usageCountSinkOverride = null;
    usageAnalyticsSinkOverride = null;
  });

  test(
    'reports nothing on the failure channel when the action succeeds',
    () async {
      final result = await tracedOperation(
        'book.import_duration_ms',
        action: () async => 'done',
        attributes: {'format': 'epub'},
      );

      expect(result, 'done');
      expect(logs.where((l) => l.warn), isEmpty);
      expect(counts, isEmpty);
    },
  );

  test('reports a failure derived from the duration metric name', () async {
    await expectLater(
      tracedOperation<void>(
        'book.import_duration_ms',
        action: () async => throw StateError('/storage/emulated/0/secret.epub'),
        attributes: {'format': 'cbz'},
      ),
      throwsStateError,
      reason: 'the operation must still surface to its caller',
    );

    // `<operation>_duration_ms` becomes `<operation>_failed`.
    final failures = logs.where((l) => l.message == 'book.import_failed');
    expect(failures, hasLength(1));
    expect(failures.single.warn, isTrue);
    expect(failures.single.attrs['format']?.value, 'cbz');
    expect(failures.single.attrs, contains('error_type'));
    // The exception text can embed a book file name.
    expect(
      failures.single.attrs.values.map((a) => a.value).join(' '),
      isNot(contains('secret')),
    );

    final counted = counts.where((c) => c.name == 'book.import_failed');
    expect(counted, hasLength(1));
    expect(counted.single.attrs?['format']?.value, 'cbz');
  });

  test('covers every traced operation, not just book imports', () async {
    await expectLater(
      tracedOperation<void>(
        'dictionary.import_duration_ms',
        action: () async => throw Exception('bad zip'),
      ),
      throwsException,
    );

    expect(logs.map((l) => l.message), contains('dictionary.import_failed'));
    expect(counts.map((c) => c.name), contains('dictionary.import_failed'));
  });

  test('uses the metric name as-is when it has no duration suffix', () async {
    await expectLater(
      tracedOperation<void>(
        'ocr.job',
        action: () async => throw Exception('boom'),
      ),
      throwsException,
    );

    expect(logs.single.message, 'ocr.job_failed');
  });
}
