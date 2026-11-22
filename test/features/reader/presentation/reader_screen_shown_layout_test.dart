// A reading-mode change is shown by a new viewer, but the one on screen
// stays until the new one can be built: while an added font is still being
// sent to it, for one. Until then, pages lay out as that viewer's mode asks,
// not the one the settings now want.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/fake_user_font_store.dart';
import '../../../shared/test_database.dart';
import 'recording_reader.dart';

/// An added font whose file is still being looked up, until [found].
class _SlowFont extends FakeUserFontStore {
  _SlowFont() : super(['Added.ttf']);

  final found = Completer<File?>();

  @override
  Future<File?> fileFor(String? fileName) =>
      fileName == null ? Future.value() : found.future;
}

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late RecordingWebViewPlatform webView;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('reader_shown_layout_');
    db = createTestDatabase();
    // The page reports loaded, so the viewer sends the book.
    InAppWebViewPlatform.instance = webView = RecordingWebViewPlatform(
      finishLoading: true,
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('switching to scroll view while a font is sent leaves the '
      'pages on screen as they were until the new viewer comes', (
    tester,
  ) async {
    // Wide enough for two pages side by side.
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final font = _SlowFont();
    final container = await openRecordedReader(
      tester,
      db: db,
      book: recordedBook(tempDir),
      settings: const ReaderSettings(epubTwoPage: true),
      fonts: font,
    );
    final shown = readerViewer(tester);
    expect(shown.scrollView, isFalse);
    expect(shown.twoPageMinWidth, kEpubTwoPageMinWidth);

    final settings = container.read(readerSettingsProvider.notifier);
    settings.setCustomFont('Added.ttf');
    await tester.pump();
    webView.sent.clear();
    settings.setScrollView(true);
    await tester.pump();
    expect(readerViewer(tester).key, shown.key, reason: 'waits for the font');

    // Still two pages.
    expect(readerViewer(tester).twoPageMinWidth, kEpubTwoPageMinWidth);
    expect(webView.sent, isNot(contains(startsWith('setTwoPage'))));

    // The font is in: the scroll view viewer replaces it.
    font.found.complete(null);
    await tester.pump();
    await tester.pump();
    expect(readerViewer(tester).key, isNot(shown.key));
    expect(readerViewer(tester).scrollView, isTrue);
    expect(readerViewer(tester).twoPageMinWidth, isNull);
    await closeRecordedReader(tester);
  });

  // A Japanese book's page reads right to left: its next page is on the
  // left. Taps beside the page need it held sideways on an iPhone.
  group('until the new viewer comes, the page on screen decides what input '
      'does', () {
    for (final (wanted, change)
        in <(String, void Function(ReaderSettingsNotifier))>[
          ('left to right', (s) => s.setReadingDirection(ReaderDirection.ltr)),
          ('scroll view', (s) => s.setScrollView(true)),
        ]) {
      for (final (input, act)
          in <(String, Future<void> Function(WidgetTester))>[
            (
              'a tap at its left edge',
              (tester) async {
                readerViewer(tester).onTouchDown!(0.02, 0.5, null);
                readerViewer(tester).onTouchUp!(0.02, 0.5, false, false, null);
              },
            ),
            (
              'the left arrow key',
              (tester) => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
            ),
            (
              'the left arrow key the page received',
              (tester) async =>
                  readerViewer(tester).onPageKey!('ArrowLeft', false),
            ),
            (
              'a tap beside its left edge',
              (tester) => tester.tapAt(const Offset(20, 220)),
            ),
          ]) {
        testWidgets('$wanted chosen: $input turns the page forward', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          const insets = FakeViewPadding(left: 62, right: 62, bottom: 20);
          tester.view
            ..physicalSize = const Size(956, 440)
            ..devicePixelRatio = 1
            ..padding = insets
            ..viewPadding = insets;
          addTearDown(tester.view.reset);
          final font = _SlowFont();
          final container = await openRecordedReader(
            tester,
            db: db,
            book: recordedBook(tempDir),
            settings: const ReaderSettings(),
            fonts: font,
          );
          final shown = readerViewer(tester);
          final settings = container.read(readerSettingsProvider.notifier);
          settings.setCustomFont('Added.ttf');
          await tester.pump();
          change(settings);
          await tester.pump();
          expect(
            readerViewer(tester).key,
            shown.key,
            reason: 'waits for the font',
          );

          webView.sent.clear();
          await act(tester);
          await tester.pump();
          expect(
            [
              for (final js in webView.sent)
                if (js == 'next()' || js == 'previous()') js,
            ],
            ['next()'],
          );

          font.found.complete(null);
          await closeRecordedReader(tester);
          // Before the test ends: the binding checks it was put back.
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  });
}
