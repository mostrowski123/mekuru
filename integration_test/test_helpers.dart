import 'package:flutter_test/flutter_test.dart';

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
