import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration tests that run in neither integration workflow, each with the
/// reason. A file leaves this table when a workflow lists it.
const _notInCi = {
  'avif_manga_test.dart': 'never listed; reason unknown',
  'dictionary_scroll_benchmark_test.dart':
      'never listed; reason unknown. A Serena memory '
      '(integration_test_webview_tap_limitations) notes it timed out on a '
      'local emulator at baseline in 2026-07',
  'furigana_export_large_test.dart':
      'local only: needs a book hundreds of MB big pushed to the device and '
      'a host to answer the system save dialog (file header)',
  'high_quality_translation_test.dart':
      'downloads Gemma 4 E2B (about 2.6 GB); its header says local only, too '
      'big for CI',
  'local_ocr_model_test.dart':
      'opt-in: needs pinned models and evaluation crops pushed to the device '
      'first (file header)',
  'reader_font_family_test.dart': 'never listed; reason unknown',
  'sentence_translation_engine_test.dart':
      'never listed; reason unknown. Its header says it downloads about 90 MB '
      'of models',
  'word_tap_lookup_furigana_above_level_test.dart': _wordTap,
  'word_tap_lookup_furigana_book_test.dart': _wordTap,
  'word_tap_lookup_furigana_on_test.dart': _wordTap,
  'word_tap_lookup_furigana_wanikani_test.dart': _wordTap,
  'word_tap_lookup_test.dart': _wordTap,
  'word_tap_lookup_vertical_test.dart':
      '$_wordTap. A Serena memory (integration_test_webview_tap_limitations) '
      'notes it failed on a local emulator at baseline in 2026-07',
};

const _wordTap =
    'iOS: no tap reaches the WKWebView under the integration-test binding '
    '(integration-ios.yml). Android: never listed; reason unknown';

const _workflows = ['integration-android.yml', 'integration-ios.yml'];

void main() {
  // The leading underscore drops _shard_test.dart, which
  // scripts/run_integration_tests.sh writes while it runs.
  final tests =
      {
        for (final f in Directory('integration_test').listSync())
          if (f is File) f.uri.pathSegments.last,
      }..removeWhere(
        (name) => !name.endsWith('_test.dart') || name.startsWith('_'),
      );
  final fileName = RegExp(r'integration_test/(\w+_test\.dart)');
  final listed = {
    for (final workflow in _workflows)
      for (final line in File('.github/workflows/$workflow').readAsLinesSync())
        if (!line.trimLeft().startsWith('#'))
          for (final m in fileName.allMatches(line)) m.group(1)!,
  };

  test('scans the integration tests and both workflows', () {
    expect(tests, isNotEmpty);
    expect(listed, isNotEmpty);
  });

  test('every integration test runs in a workflow or is excluded', () {
    final missing = [
      for (final name in tests)
        if (!listed.contains(name) && !_notInCi.containsKey(name))
          '$name runs in no workflow. Add it to integration-android.yml or '
              'integration-ios.yml, or to the exclusion table with a reason.',
    ]..sort();
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('the exclusion table names only existing, unlisted files', () {
    final stale = [
      for (final name in _notInCi.keys)
        if (!tests.contains(name))
          '$name is in the exclusion table but no longer exists. Remove it '
              'from the table.'
        else if (listed.contains(name))
          '$name is in the exclusion table but now runs in a workflow. Remove '
              'it from the table.',
    ];
    expect(stale, isEmpty, reason: stale.join('\n'));
  });
}
