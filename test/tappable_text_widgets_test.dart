import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';

Finder _richTextWithPlainText(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) return false;
    final span = widget.text;
    return span.toPlainText() == text;
  });
}

Future<void> _tapCharacterInRichText(
  WidgetTester tester,
  Finder richTextFinder, {
  required int offset,
}) async {
  final renderParagraph = tester.renderObject<RenderParagraph>(richTextFinder);
  final boxes = renderParagraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  expect(
    boxes,
    isNotEmpty,
    reason: 'No selection box found for offset $offset',
  );

  final globalPosition = renderParagraph.localToGlobal(
    boxes.first.toRect().center,
  );
  await tester.tapAt(globalPosition);
}

void main() {
  testWidgets(
    'TappableDefinitionText only fires for Japanese runs in mixed content',
    (tester) async {
      final tappedWords = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: TappableDefinitionText(
                text: 'See 日本語 and 英語 examples',
                onWordTap: tappedWords.add,
              ),
            ),
          ),
        ),
      );

      final richText = _richTextWithPlainText('See 日本語 and 英語 examples');
      expect(richText, findsOneWidget);

      await _tapCharacterInRichText(tester, richText, offset: 5);
      await tester.pump();

      await _tapCharacterInRichText(tester, richText, offset: 1);
      await tester.pump();

      await _tapCharacterInRichText(tester, richText, offset: 13);
      await tester.pump();

      expect(tappedWords, ['日本語', '英語']);
    },
  );

  testWidgets(
    'TappableDefinitionText still maps taps correctly when text wraps',
    (tester) async {
      final tappedWords = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: TappableDefinitionText(
                text: 'Meaning 日本語 details 英語 sample',
                onWordTap: tappedWords.add,
              ),
            ),
          ),
        ),
      );

      final richText = _richTextWithPlainText('Meaning 日本語 details 英語 sample');
      expect(richText, findsOneWidget);

      await _tapCharacterInRichText(tester, richText, offset: 20);
      await tester.pump();

      expect(tappedWords, ['英語']);
    },
  );

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
    'TappableExpressionText only fires for kanji, not furigana or kana',
    (tester) async {
      final tappedKanji = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TappableExpressionText(
              expression: '食べる',
              reading: 'たべる',
              onKanjiTap: tappedKanji.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('た'));
      await tester.pump();
      expect(tappedKanji, isEmpty);

      await _tapCharacterInRichText(
        tester,
        _richTextWithPlainText('べる'),
        offset: 0,
      );
      await tester.pump();
      expect(tappedKanji, isEmpty);

      await _tapCharacterInRichText(
        tester,
        _richTextWithPlainText('食'),
        offset: 0,
      );
      await tester.pump();
      expect(tappedKanji, ['食']);
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
