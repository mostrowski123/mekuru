import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The localizations the app will actually resolve for the test device's
/// locale — assert against these, not hardcoded English.
Future<AppLocalizations> loadExpectedL10n() {
  final locale = resolveSupportedAppLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
    AppLocalizations.supportedLocales,
  );
  return AppLocalizations.delegate.load(locale);
}

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

/// Long-presses a library book tile until its options sheet is up.
///
/// _BookTile's options timer is its own 500ms Timer on a raw Listener;
/// tester.longPress pumps exactly kLongPressTimeout (500ms) and races it,
/// so this holds for 650ms instead.
///
/// The pointer must be MOUSE-kind: with a touch pointer the grid's drag
/// recognizer eager-wins the arena on down, and when the options sheet
/// pushes mid-hold the navigator cancels the pointer under the test
/// binding's feet — the recognizer never sees a terminal event and stays
/// "accepted" forever, eating every later tap on the grid. Scrollables
/// don't compete for mouse drags, so a mouse pointer sidesteps the whole
/// failure mode; the tile's raw Listener is kind-agnostic.
///
/// While tiles are mounted, never pumpAndSettle — _CoverTilt's sensor
/// stream rebuilds at 60fps on device and the frame never settles.
Future<void> longPressTile(WidgetTester tester, Finder tile) async {
  final gesture = await tester.startGesture(
    tester.getCenter(tile),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 650));
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // sheet slides in
}

/// Taps a labelled row in the currently open bottom sheet.
///
/// The library options sheet is a SingleChildScrollView and can clip lower
/// tiles on short screens, hence the ensureVisible.
Future<void> tapSheetItem(WidgetTester tester, String label) async {
  final item = find.text(label);
  await tester.ensureVisible(item);
  await tester.pump();
  await tester.tap(item);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Deletes the app-support `books/` directory so imported fixture EPUBs from
/// a previous test run don't leak into the current one.
/// The real on-device `books/` root that imports write into.
Future<Directory> appBooksDir() async {
  final appDir = await getApplicationSupportDirectory();
  return Directory(p.join(appDir.path, 'books'));
}

Future<void> cleanupAppBooksDir() async {
  final booksDir = await appBooksDir();
  if (await booksDir.exists()) {
    await booksDir.delete(recursive: true);
  }
}
