import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/sentry_setup.dart';

void main() {
  test('release installs are bucketed by installer store', () {
    expect(sentryEnvironmentForInstaller('com.android.vending'), 'play-store');
    expect(sentryEnvironmentForInstaller('com.apple'), 'app-store');
    expect(sentryEnvironmentForInstaller('com.apple.testflight'), 'testflight');
    expect(sentryEnvironmentForInstaller(null), 'sideload');
    expect(sentryEnvironmentForInstaller('com.apple.simulator'), 'sideload');
  });
}
