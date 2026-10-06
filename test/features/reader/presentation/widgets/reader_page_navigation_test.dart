import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
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

  group('readerKeyIntent', () {
    ReaderNavigationIntent intent(
      LogicalKeyboardKey key, {
      ReaderDirection direction = ReaderDirection.rtl,
      VolumeKeyPageTurn volumeKeys = VolumeKeyPageTurn.downNext,
      bool shift = false,
    }) => readerKeyIntent(
      key,
      direction: direction,
      volumeKeys: volumeKeys,
      shift: shift,
    );

    const forward = ReaderNavigationIntent.goForward;
    const backward = ReaderNavigationIntent.goBackward;
    const none = ReaderNavigationIntent.none;

    test('volume buttons follow the setting', () {
      expect(intent(LogicalKeyboardKey.audioVolumeDown), forward);
      expect(intent(LogicalKeyboardKey.audioVolumeUp), backward);
      const upNext = VolumeKeyPageTurn.upNext;
      expect(
        intent(LogicalKeyboardKey.audioVolumeDown, volumeKeys: upNext),
        backward,
      );
      expect(
        intent(LogicalKeyboardKey.audioVolumeUp, volumeKeys: upNext),
        forward,
      );
      const off = VolumeKeyPageTurn.off;
      expect(intent(LogicalKeyboardKey.audioVolumeDown, volumeKeys: off), none);
      expect(intent(LogicalKeyboardKey.audioVolumeUp, volumeKeys: off), none);
    });

    test('left and right follow the reading direction', () {
      expect(intent(LogicalKeyboardKey.arrowLeft), forward);
      expect(intent(LogicalKeyboardKey.arrowRight), backward);
      const ltr = ReaderDirection.ltr;
      expect(intent(LogicalKeyboardKey.arrowLeft, direction: ltr), backward);
      expect(intent(LogicalKeyboardKey.arrowRight, direction: ltr), forward);
    });

    test('page keys, up and down, and space turn pages', () {
      expect(intent(LogicalKeyboardKey.pageDown), forward);
      expect(intent(LogicalKeyboardKey.arrowDown), forward);
      expect(intent(LogicalKeyboardKey.space), forward);
      expect(intent(LogicalKeyboardKey.pageUp), backward);
      expect(intent(LogicalKeyboardKey.arrowUp), backward);
      expect(intent(LogicalKeyboardKey.space, shift: true), backward);
      expect(intent(LogicalKeyboardKey.keyA), none);
    });
  });

  testWidgets(
    'volume buttons turn pages on Android and are left alone on iOS',
    (tester) async {
      final intents = <ReaderNavigationIntent>[];
      Future<bool> pressVolumeDown(TargetPlatform platform) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          ReaderKeyNavigation(
            direction: ReaderDirection.rtl,
            volumeKeys: VolumeKeyPageTurn.downNext,
            onIntent: intents.add,
            child: const SizedBox(),
          ),
        );
        final handled = await tester.sendKeyDownEvent(
          LogicalKeyboardKey.audioVolumeDown,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeDown);
        debugDefaultTargetPlatformOverride = null;
        return handled;
      }

      expect(await pressVolumeDown(TargetPlatform.android), isTrue);
      expect(intents, [ReaderNavigationIntent.goForward]);

      expect(await pressVolumeDown(TargetPlatform.iOS), isFalse);
      expect(intents, [ReaderNavigationIntent.goForward]);
    },
  );

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
