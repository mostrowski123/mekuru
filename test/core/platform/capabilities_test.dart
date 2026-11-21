import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/capabilities.dart';

void main() {
  test('each platform answers every capability', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const table = {
      TargetPlatform.android: (
        LongWork.systemJob,
        Wording.android,
        'Google Play',
        'AnkiDroid',
      ),
      TargetPlatform.iOS: (LongWork.inApp, Wording.ios, 'App Store', 'Anki'),
    };
    table.forEach((platform, expected) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        (longWork, wording, storeName, ankiAppName),
        expected,
        reason: '$platform',
      );
    });
  });
}
