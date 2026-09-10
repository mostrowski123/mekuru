// One scenario per file — see integration_test/shared/word_tap_scenario.dart
// for the fixture, the diagnostic-log legend, and why scenarios must not
// share a process.

import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/word_tap_scenario.dart';

void main() {
  registerWordTapScenario(
    'authored ruby is classified against the WaniKani known set and taps '
    'still work (wanikani mode, vertical-rl with ruby)',
    furiganaMode: FuriganaMode.wanikani,
    verticalWithRuby: true,
    expectAuthoredRubyClassification: true,
    // Every kanji in the fixture's ruby words (学校, 日本語) is burned, so
    // at the default Burned threshold all authored ruby is below level.
    wanikaniStages: {for (final rune in '学校日本語'.runes) rune: 9},
  );
}
