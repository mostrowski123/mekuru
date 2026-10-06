import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_page_navigation.dart';
import 'package:mekuru/shared/widgets/reader_seek_bar.dart';

import '../../../../test_app.dart';

void main() {
  testWidgets('screen readers can show the controls and turn pages', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final intents = <ReaderNavigationIntent>[];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ReaderPageSemantics(
          label: 'Page 3 of 120',
          onIntent: intents.add,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final page = find.semantics.byLabel('Page 3 of 120');
    final next = CustomSemanticsAction(label: 'Next page');
    final previous = CustomSemanticsAction(label: 'Previous page');
    final tapHint = CustomSemanticsAction.overridingAction(
      hint: 'show or hide controls',
      action: SemanticsAction.tap,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Page 3 of 120')),
      isSemantics(hasTapAction: true, customActions: [next, previous, tapHint]),
    );

    tester.semantics.tap(page);
    tester.semantics.customAction(page, next);
    tester.semantics.customAction(page, previous);
    expect(intents, [
      ReaderNavigationIntent.toggleControls,
      ReaderNavigationIntent.goForward,
      ReaderNavigationIntent.goBackward,
    ]);
    semantics.dispose();
  });

  testWidgets('the seek bar reads its position the way the reader asks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Scaffold(
          body: ReaderSeekBar(
            value: 2,
            max: 119,
            divisions: 119,
            isRtl: false,
            leadingLabel: (value) => '${value.round() + 1}',
            trailingLabel: '120',
            semanticValue: (value) => 'Page ${value.round() + 1} of 120',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(Slider)),
      isSemantics(label: 'Reading position', value: 'Page 3 of 120'),
    );
    semantics.dispose();
  });
}
