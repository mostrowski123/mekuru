// The normal app (not a test), seeded with the screenshot library, for the
// App Store screenshots that need real touches: under the integration-test
// binding on iOS no tap reaches the reader's web view, so a dictionary lookup
// can only be shown this way.
//
//   flutter run -t integration_test/app_store_screenshot_app.dart -d <simulator>
//
// Then drive it by hand (or with a simulator tool) and capture with
// `xcrun simctl io <udid> screenshot`. The database is in memory; imported
// book folders are left for the app's own orphan sweep.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/screenshot_seed.dart';
import 'shared/test_infrastructure.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = createTestDatabase();
  final work = await Directory(
    p.join((await getTemporaryDirectory()).path, 'shots'),
  ).create(recursive: true);
  await seedScreenshotLibrary(db, work);
  await MecabService.instance.init();
  runApp(buildIntegrationTestRealApp(db: db));
}
