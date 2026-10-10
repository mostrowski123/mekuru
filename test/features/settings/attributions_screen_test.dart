import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/screens/attributions_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../test_app.dart';

void main() {
  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'Mekuru',
      packageName: 'moe.matthew.mekuru',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  testWidgets(
    'credits the Android translation engines on Android only',
    (tester) async {
      // Tall enough that the list builds every card, and wide enough for
      // the test font's titles.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 30000);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildLocalizedTestApp(home: const AttributionsScreen()),
      );
      await tester.pumpAndSettle();

      final shown = defaultTargetPlatform == TargetPlatform.android
          ? findsOneWidget
          : findsNothing;
      expect(find.text('Firefox Translations'), shown);
      expect(find.text('Gemma 4'), shown);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
