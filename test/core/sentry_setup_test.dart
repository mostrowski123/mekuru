import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/sentry_setup.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  late SentryOptions options;
  final logged = <String>[];

  setUp(() {
    options = SentryOptions();
    applySharedSentryOptions(options, (
      environment: 'debug',
      isSynthetic: true,
    ));
    logged.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logged.add(message);
    usageAnalyticsSinkOverride = (name, parameters) {};
  });
  tearDown(() {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
  });

  test('a crash from a full disk is logged, not sent as an issue', () async {
    final event = SentryEvent(
      throwable: const FileSystemException(
        'Write failed',
        'cache.json',
        OSError('No space left on device', 28),
      ),
    );

    expect(await options.beforeSend!(event, Hint()), isNull);
    expect(logged, ['app.user_side_error']);
  });

  test('any other crash is sent', () async {
    final event = SentryEvent(throwable: StateError('boom'));

    expect(await options.beforeSend!(event, Hint()), isNotNull);
    expect(logged, isEmpty);
  });
}
