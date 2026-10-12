import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/presentation/widgets/manga_manifest_picker_sheet.dart';

import '../../../../test_app.dart';

void main() {
  test('defaultManifestSelection ticks one manifest per volume', () {
    expect(
      defaultManifestSelection([
        'vol1.html',
        'vol1.mokuro',
        'vol2.html',
        'Vol3.MOKURO',
        'vol3.html',
      ]),
      {'vol1.mokuro', 'vol2.html', 'Vol3.MOKURO'},
    );
  });

  group('showMangaManifestPickerSheet', () {
    /// Opens the sheet for [files]; the returned list is filled once it
    /// closes.
    Future<List<List<String>?>> open(
      WidgetTester tester,
      List<String> files,
    ) async {
      final results = <List<String>?>[];
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showMangaManifestPickerSheet(
                  context,
                  files: files,
                  folderLabel: 'Manga',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('imports the preselected volumes in list order', (
      tester,
    ) async {
      final results = await open(tester, [
        'vol1.html',
        'vol1.mokuro',
        'vol2.mokuro',
      ]);

      expect(find.text('3 manga files found'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(results, [
        ['vol1.mokuro', 'vol2.mokuro'],
      ]);
    });

    testWidgets('returns what the user ticks; nothing ticked disables Import', (
      tester,
    ) async {
      final results = await open(tester, ['vol1.mokuro', 'vol2.mokuro']);

      await tester.tap(find.text('vol1.mokuro'));
      await tester.tap(find.text('vol2.mokuro'));
      await tester.pump();
      final import = find.widgetWithText(FilledButton, 'Import');
      expect(tester.widget<FilledButton>(import).onPressed, isNull);

      await tester.tap(find.text('vol2.mokuro'));
      await tester.pump();
      await tester.tap(import);
      await tester.pumpAndSettle();

      expect(results, [
        ['vol2.mokuro'],
      ]);
    });
  });
}
