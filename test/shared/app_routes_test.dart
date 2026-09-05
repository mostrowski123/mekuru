import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every pushed screen must carry a static route name, or it silently drops
/// out of Sentry's screen transactions and breadcrumbs and Firebase's
/// screen_view. Rather than trusting 40 call sites, this pins the mechanism:
/// `MaterialPageRoute` only inside `namedRoute`, custom routes always named,
/// and names that look like telemetry ids.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('scans the lib tree (runs from the package root)', () {
    expect(files, isNotEmpty);
  });

  test('MaterialPageRoute is constructed only by namedRoute', () {
    final offenders = [
      for (final f in files)
        if (!f.path.endsWith('app_routes.dart') &&
            f.readAsStringSync().contains('MaterialPageRoute'))
          f.path,
    ];
    expect(offenders, isEmpty, reason: 'push namedRoute(...) instead');
  });

  test('custom PageRouteBuilders are named', () {
    final unnamed = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in 'PageRouteBuilder'.allMatches(src)) {
        final window = src.substring(m.end, (m.end + 200).clamp(0, src.length));
        if (!window.contains('RouteSettings(name:')) unnamed.add(f.path);
      }
    }
    expect(unnamed, isEmpty);
  });

  test('route names are snake_case ids, not titles', () {
    final name = RegExp(r"namedRoute(?:<\w+>)?\(\s*'([^']*)'");
    final bad = <String>[];
    for (final f in files) {
      for (final m in name.allMatches(f.readAsStringSync())) {
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(m.group(1)!)) {
          bad.add('${f.path}: ${m.group(1)}');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
