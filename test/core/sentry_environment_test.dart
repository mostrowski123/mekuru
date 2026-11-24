import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/sentry_setup.dart';

void main() {
  test('release installs are bucketed by installer store', () {
    expect(sentryEnvironmentForInstaller('com.android.vending'), 'play-store');
    expect(sentryEnvironmentForInstaller('com.apple'), 'ios');
    expect(sentryEnvironmentForInstaller('com.apple.testflight'), 'ios');
    expect(sentryEnvironmentForInstaller('com.apple.simulator'), 'ios');
    expect(sentryEnvironmentForInstaller(null), 'sideload');
  });

  test('the analytics install source names the store exactly', () {
    expect(installSourceFor('com.android.vending'), 'play');
    expect(installSourceFor('com.apple'), 'app_store');
    expect(installSourceFor('com.apple.testflight'), 'testflight');
    expect(installSourceFor('com.apple.simulator'), 'sideload');
    expect(installSourceFor('com.amazon.venezia'), 'sideload');
    expect(installSourceFor(null), 'sideload');
  });
}
