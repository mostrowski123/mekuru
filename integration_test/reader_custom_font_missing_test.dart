// A reading-data backup restored on another phone names a font that was
// never added there: opening a book says the book's own fonts are shown.
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = 'フォント追加テスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_custom_font_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a book opened with a missing added font says so', (
    tester,
  ) async {
    await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(
        fontFamily: ReaderFontFamily.custom,
        customFontFile: 'Missing.ttf',
      ),
    );
    expect(
      find.widgetWithText(SnackBar, AppLocalizationsEn().readerUserFontFailed),
      findsOneWidget,
    );
  });
}
