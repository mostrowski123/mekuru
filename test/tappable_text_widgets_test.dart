import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';

void main() {
  testWidgets(
    'TappableDefinitionText still fires taps after an unrelated parent rebuild',
    (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _RebuildHarness(
              child: TappableDefinitionText(
                text: '日本語',
                onWordTap: (_) => tapCount++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('日本語', findRichText: true));
      await tester.pump();
      expect(tapCount, 1);

      await tester.tap(find.byKey(_RebuildHarness.rebuildButtonKey));
      await tester.pump();

      await tester.tap(find.text('日本語', findRichText: true));
      await tester.pump();
      expect(tapCount, 2);
    },
  );

  testWidgets(
    'TappableExpressionText still fires kanji taps after an unrelated parent rebuild',
    (tester) async {
      var tappedKanji = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _RebuildHarness(
              child: TappableExpressionText(
                expression: '食',
                reading: 'た',
                onKanjiTap: tappedKanji.add,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('食', findRichText: true));
      await tester.pump();
      expect(tappedKanji, ['食']);

      await tester.tap(find.byKey(_RebuildHarness.rebuildButtonKey));
      await tester.pump();

      await tester.tap(find.text('食', findRichText: true));
      await tester.pump();
      expect(tappedKanji, ['食', '食']);
    },
  );
}

class _RebuildHarness extends StatefulWidget {
  const _RebuildHarness({required this.child});

  static const rebuildButtonKey = Key('rebuild-button');

  final Widget child;

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  var _buildCount = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('build: $_buildCount'),
        widget.child,
        TextButton(
          key: _RebuildHarness.rebuildButtonKey,
          onPressed: () {
            setState(() {
              _buildCount++;
            });
          },
          child: const Text('Rebuild'),
        ),
      ],
    );
  }
}
