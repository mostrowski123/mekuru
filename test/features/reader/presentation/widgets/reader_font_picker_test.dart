import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/providers/user_font_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_font_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/fake_user_font_store.dart';
import '../../../../test_app.dart';

void main() {
  late FakeUserFontStore store;
  late ProviderContainer container;
  String? pickedPath;

  Future<void> openPicker(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        userFontStoreProvider.overrideWithValue(store),
        userFontFilePickerProvider.overrideWithValue(() async => pickedPath),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderFontPicker(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder checkedRow(String label) => find.descendant(
    of: find.widgetWithText(ListTile, label),
    matching: find.byIcon(Icons.check),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FakeUserFontStore(['Kaisei.ttf']);
    pickedPath = '/picked/New.ttf';
  });

  testWidgets('lists the built-in fonts, the added ones and Add font…', (
    tester,
  ) async {
    await openPicker(tester);
    for (final label in [
      'Book default',
      'Mincho',
      'Gothic',
      'Kaisei',
      'Add font…',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Book default is chosen out of the box.
    expect(checkedRow('Book default'), findsOneWidget);
  });

  testWidgets('choosing an added font selects it by file name', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('Kaisei'));
    await tester.pumpAndSettle();

    final settings = container.read(readerSettingsProvider);
    expect(settings.fontFamily, ReaderFontFamily.custom);
    expect(settings.customFontFile, 'Kaisei.ttf');
  });

  testWidgets('a selected font whose file is gone shows Book default', (
    tester,
  ) async {
    await openPicker(tester);
    Navigator.of(tester.element(find.text('Kaisei'))).pop();
    await tester.pumpAndSettle();
    container.read(readerSettingsProvider.notifier).setCustomFont('Gone.ttf');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(checkedRow('Book default'), findsOneWidget);
  });

  test('selectedReaderFont reads a missing added font as Book default', () {
    const fonts = [UserFont(fileName: 'Kaisei.ttf')];
    expect(
      selectedReaderFont(
        const ReaderSettings(
          fontFamily: ReaderFontFamily.custom,
          customFontFile: 'Gone.ttf',
        ),
        fonts,
      ),
      (family: ReaderFontFamily.book, font: null),
    );
    expect(
      selectedReaderFont(
        const ReaderSettings(
          fontFamily: ReaderFontFamily.custom,
          customFontFile: 'Kaisei.ttf',
        ),
        fonts,
      ).font,
      fonts.single,
    );
  });

  testWidgets('Add font… imports the picked file and selects it', (
    tester,
  ) async {
    await openPicker(tester);
    await tester.tap(find.text('Add font…'));
    await tester.pumpAndSettle();

    expect(store.fileNames, contains('Added.ttf'));
    expect(container.read(readerSettingsProvider).customFontFile, 'Added.ttf');
    expect(find.text('Add font…'), findsNothing); // the sheet closed
  });

  testWidgets('a refused file explains why and changes nothing', (
    tester,
  ) async {
    store.nextImport = const UserFontImportException(
      UserFontImportError.collection,
    );
    await openPicker(tester);
    await tester.tap(find.text('Add font…'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Font collections (.ttc) aren't supported. Pick a .ttf or .otf file.",
      ),
      findsOneWidget,
    );
    expect(
      container.read(readerSettingsProvider).fontFamily,
      ReaderFontFamily.book,
    );
  });

  testWidgets('a refused file is explained above the reader settings sheet', (
    tester,
  ) async {
    // In the reader the picker opens from the quick-settings sheet, which
    // would cover a snack bar.
    store.nextImport = const UserFontImportException(
      UserFontImportError.notAFont,
    );
    container = ProviderContainer(
      overrides: [
        userFontStoreProvider.overrideWithValue(store),
        userFontFilePickerProvider.overrideWithValue(() async => pickedPath),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => TextButton(
                    onPressed: () => showReaderFontPicker(sheetContext),
                    child: const Text('fonts'),
                  ),
                ),
                child: const Text('sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fonts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add font…'));
    await tester.pumpAndSettle();

    expect(find.text("This file isn't a font.").hitTestable(), findsOneWidget);
  });

  testWidgets('cancelling the file picker changes nothing', (tester) async {
    pickedPath = null;
    await openPicker(tester);
    await tester.tap(find.text('Add font…'));
    await tester.pumpAndSettle();
    expect(store.fileNames, ['Kaisei.ttf']);
  });

  testWidgets(
    'removing the selected font asks, then goes back to Book default',
    (tester) async {
      await openPicker(tester);
      container
          .read(readerSettingsProvider.notifier)
          .setCustomFont('Kaisei.ttf');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove font'));
      await tester.pumpAndSettle();
      expect(find.text('Remove font?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(store.fileNames, isEmpty);
      expect(
        container.read(readerSettingsProvider).fontFamily,
        ReaderFontFamily.book,
      );
    },
  );
}
