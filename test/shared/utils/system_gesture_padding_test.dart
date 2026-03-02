import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/utils/system_gesture_padding.dart';

void main() {
  test('keeps a minimum gap when no system gesture inset is present', () {
    const mediaQueryData = MediaQueryData();

    expect(bottomControlPadding(mediaQueryData), 8.0);
  });

  test('adds clearance when gestures extend beyond the safe area', () {
    const mediaQueryData = MediaQueryData(
      systemGestureInsets: EdgeInsets.only(bottom: 18),
    );

    expect(bottomControlPadding(mediaQueryData), 26.0);
  });

  test(
    'does not double count safe-area padding already handled by SafeArea',
    () {
      const mediaQueryData = MediaQueryData(
        padding: EdgeInsets.only(bottom: 34),
        systemGestureInsets: EdgeInsets.only(bottom: 16),
      );

      expect(bottomControlPadding(mediaQueryData), 8.0);
    },
  );
}
