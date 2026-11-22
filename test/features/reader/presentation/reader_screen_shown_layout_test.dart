// A reading-mode change is shown by a new viewer, but the one on screen
// stays until the new one can be built: while an added font is still being
// sent to it, for one. Until then, pages lay out as that viewer's mode asks,
// not the one the settings now want.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
}
