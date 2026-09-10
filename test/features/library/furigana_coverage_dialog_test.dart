import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import '../../test_app.dart';

/// Result of the last closed dialog, `null` while open or after cancel.
class _Outcome {
  (FuriganaMode, int)? result;
  bool closed = false;
}

Future<_Outcome> _openDialog(
  WidgetTester tester, {
  required bool offerWanikani,
}) async {
  final outcome = _Outcome();
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            outcome.result = await showFuriganaCoverageDialog(
              context,
              initialLevel: 3,
              offerWanikani: offerWanikani,
            );
            outcome.closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Furigana in exported book'), findsOneWidget);
  return outcome;
}

void main() {
  testWidgets('hides the WaniKani option until kanji are synced', (
    tester,
  ) async {
    final outcome = await _openDialog(tester, offerWanikani: false);

    expect(find.text('Kanji not yet known on WaniKani'), findsNothing);
    expect(find.text('All kanji'), findsOneWidget);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(outcome.result, (FuriganaMode.all, 3));
  });

  testWidgets('offers WaniKani and returns it when chosen', (tester) async {
    final outcome = await _openDialog(tester, offerWanikani: true);

    await tester.tap(find.text('Kanji not yet known on WaniKani'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.result, (FuriganaMode.wanikani, 3));
  });

  testWidgets('cancel returns nothing', (tester) async {
    final outcome = await _openDialog(tester, offerWanikani: true);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome.closed, isTrue);
    expect(outcome.result, isNull);
  });
}
