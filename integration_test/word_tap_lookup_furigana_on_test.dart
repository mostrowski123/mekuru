// One scenario per file — see integration_test/shared/word_tap_scenario.dart
// for the fixture, the diagnostic-log legend, and why scenarios must not
// share a process.

import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/word_tap_scenario.dart';

void main() {
  registerWordTapScenario(
    'tapping text opens the lookup sheet (furigana on)',
    furiganaMode: FuriganaMode.all,
  );
}
