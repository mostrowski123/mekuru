import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var tick = 0; tick < maxTicks; tick++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for $finder after $timeout.');
}

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var tick = 0; tick < maxTicks; tick++) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }

  throw TestFailure(
    'Timed out waiting for $finder to disappear after $timeout.',
  );
}

/// Deletes the app-support `books/` directory so imported fixture EPUBs from
/// a previous test run don't leak into the current one.
Future<void> cleanupAppBooksDir() async {
  final appDir = await getApplicationSupportDirectory();
  final booksDir = Directory(p.join(appDir.path, 'books'));
  if (await booksDir.exists()) {
    await booksDir.delete(recursive: true);
  }
}
