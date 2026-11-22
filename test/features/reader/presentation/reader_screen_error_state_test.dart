// A book that does not open says so in words and buttons that stay readable
// whatever the app's theme and the colours of the reader's page.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import 'recording_reader.dart';

final _en = AppLocalizationsEn();
final _seed = AppColorTheme.mekuruRed.seedColor;

/// The WCAG contrast ratio of [a] and [b], from 1 to 21.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colour [text] is drawn in.
Color _ink(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).text.style!.color!;

/// The opaque colour nearest behind [finder].
Color _behind(WidgetTester tester, Finder finder) {
  Color? found;
  tester.element(finder).visitAncestorElements((element) {
    final color = switch (element.widget) {
      Material(:final color?) => color,
      ColoredBox(:final color) => color,
      _ => null,
    };
    if (color != null && color.a == 1) found = color;
    return found == null;
  });
  return found!;
}

void main() {
  late Directory tempDir;
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('reader_error_state_');
    db = createTestDatabase();
    InAppWebViewPlatform.instance = RecordingWebViewPlatform();
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  /// The message, the icon and both buttons stand out from what is behind
  /// them: 4.5:1 for words, 3:1 for the icon.
  void expectReadable(WidgetTester tester, String message) {
    for (final (what, finder, least) in [
      ('the message', find.text(message), 4.5),
      (
        'the icon',
        find.descendant(
          of: find.byIcon(Icons.error_outline),
          matching: find.byType(RichText),
        ),
        3.0,
      ),
      ('Retry', find.text(_en.commonRetry), 4.5),
      ('Back', find.text(_en.commonBack), 4.5),
    ]) {
      final ink = _ink(tester, finder);
      final behind = _behind(tester, finder);
      expect(
        _contrast(ink, behind),
        greaterThanOrEqualTo(least),
        reason: '$what: $ink on $behind',
      );
    }
  }

  for (final (app, theme) in [
    ('light', AppTheme.lightTheme(_seed)),
    ('dark', AppTheme.darkTheme(_seed)),
    ('pure black', AppTheme.darkTheme(_seed, pureBlack: true)),
  ]) {
    for (final page in ColorMode.values) {
      testWidgets('$app app, ${page.name} page', (tester) async {
        await openRecordedReader(
          tester,
          db: db,
          book: recordedBook(tempDir),
          settings: ReaderSettings(colorMode: page),
          theme: theme,
          loaded: false,
        );

        readerViewer(tester).onLoadError!('net::ERR_FAILED');
        await tester.pump();
        expectReadable(tester, _en.readerCouldNotOpen);

        await tester.tap(find.text(_en.commonRetry));
        await pumpUntilViewerBuilt(tester);
        await tester.pump(const Duration(seconds: 15));
        expectReadable(tester, _en.readerLoadTimeout);

        await tester.tap(find.text(_en.commonRetry));
        await pumpUntilViewerBuilt(tester);
        readerViewer(tester).onRendererGone!();
        await tester.pump();
        expectReadable(tester, _en.readerStoppedWhileOpening);
        await closeRecordedReader(tester);
      });
    }
  }
}
