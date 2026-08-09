// One scenario per file — see integration_test/shared/word_tap_scenario.dart
// for the fixture, the diagnostic-log legend, and why scenarios must not
// share a process.

import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/word_tap_scenario.dart';

void main() {
  registerWordTapScenario(
    'authored ruby is classified against the JLPT level and taps still work '
    '(aboveLevel mode, vertical-rl with ruby)',
    furiganaMode: FuriganaMode.aboveLevel,
    verticalWithRuby: true,
    expectAuthoredRubyClassification: true,
  );
}
