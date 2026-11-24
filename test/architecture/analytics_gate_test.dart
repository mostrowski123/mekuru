import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Firebase Analytics starts off natively and is turned on only in builds
/// the release workflows make with [_define]. Every way this breaks is
/// silent in the app: emulators and CI builds counted as readers, or no
/// reader counted at all.
const _define = '--dart-define=OFFICIAL_BUILD=true';
const _releaseWorkflows = {'build-release.yml', 'release-ios.yml'};

String _withoutXmlComments(String source) =>
    source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Each `flutter build` command in the workflow's steps, from `flutter
/// build` to the next one in the same step or the step's end.
List<String> _buildCommands(String workflow) {
  final jobs = (loadYaml(workflow) as YamlMap)['jobs'] as YamlMap;
  return [
    for (final job in jobs.values)
      for (final step in (job as YamlMap)['steps'] as YamlList? ?? const [])
        if ((step as YamlMap)['run'] case final String run)
          ...run.split('flutter build ').skip(1),
  ];
}

void main() {
  final workflows = {
    for (final f in Directory('.github/workflows').listSync())
      if (f is File && f.path.endsWith('.yml'))
        f.uri.pathSegments.last: f.readAsStringSync(),
  };

  test('every release build passes $_define', () {
    for (final name in _releaseWorkflows) {
      final commands = _buildCommands(workflows[name]!);
      expect(commands, isNotEmpty, reason: '$name has no flutter build step.');
      for (final command in commands) {
        expect(
          command,
          contains(_define),
          reason:
              'flutter build $command\nin $name does not pass $_define, so '
              'its installs never report to Firebase Analytics.',
        );
      }
    }
  });

  test('no other workflow builds an official build', () {
    final others = [
      for (final MapEntry(key: name, value: source) in workflows.entries)
        if (!_releaseWorkflows.contains(name) &&
            source.contains('OFFICIAL_BUILD'))
          name,
    ];
    expect(
      others,
      isEmpty,
      reason:
          'Only build-release.yml and release-ios.yml make builds that '
          'report to Firebase Analytics. A CI test build that passes '
          'OFFICIAL_BUILD counts its emulators as readers.',
    );
  });

  // Off until AnalyticsService decides, so the native SDK's own events
  // (first_open, session_start) never come from a build that should not
  // report.
  for (final (platform, path, setting) in [
    (
      'Android',
      'android/app/src/main/AndroidManifest.xml',
      r'<meta-data\s+android:name="firebase_analytics_collection_enabled"'
          r'\s+android:value="false"\s*/>',
    ),
    (
      'iOS',
      'ios/Runner/Info.plist',
      r'<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>\s*<false/>',
    ),
  ]) {
    test('$platform starts with Firebase Analytics off', () {
      final source = _withoutXmlComments(File(path).readAsStringSync());
      expect(
        RegExp(setting).hasMatch(source),
        isTrue,
        reason: '$path does not turn Firebase Analytics collection off.',
      );
    });
  }
}
