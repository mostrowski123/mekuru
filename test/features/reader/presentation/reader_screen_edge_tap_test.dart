// Taps beside the page. iOS keeps the EPUB page clear of the Dynamic
// Island, the notch and iPhone Duo's strip, so held sideways the page ends
// short of the screen's edges; a tap there acts as a tap at that edge of
// the page.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import 'recording_reader.dart';

/// iPhone 18 Pro Max held sideways, either way round: the Dynamic Island's
/// side and the other are inset alike.
const _landscape = Size(956, 440);
const _landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 20);

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late List<String> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('reader_edge_tap_');
    db = createTestDatabase();
    final webView = RecordingWebViewPlatform();
    InAppWebViewPlatform.instance = webView;
    sent = webView.sent;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Finder viewerFinder() => readerViewerFinder();
  CustomEpubViewer viewer(WidgetTester tester) => readerViewer(tester);

  /// The page turns the reader asked the page for.
  List<String> turns() => [
    for (final js in sent)
      if (js == 'next()' || js == 'previous()') js,
  ];

  void screen(
    WidgetTester tester, {
    required TargetPlatform platform,
    required Size size,
    required FakeViewPadding insets,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = insets
      ..viewPadding = insets;
    addTearDown(tester.view.reset);
  }

  /// Opens a Japanese book (right to left), or one read [direction], with
  /// no page turn animation.
  Future<void> openReader(
    WidgetTester tester, {
    String? direction,
    bool scrollView = false,
  }) => openRecordedReader(
    tester,
    db: db,
    book: recordedBook(tempDir, direction: direction),
    settings: ReaderSettings(
      pageTurnStyle: PageTurnStyle.none,
      scrollView: scrollView,
    ),
  );

  Future<void> closeReader(WidgetTester tester) async {
    await closeRecordedReader(tester);
    // Before the test ends: the binding checks it was put back.
    debugDefaultTargetPlatformOverride = null;
  }

  /// A tap on the page as the bridge reports it, at [x] across the page.
  Future<void> tapPage(WidgetTester tester, double x) async {
    viewer(tester).onTouchDown!(x, 0.5, null);
    viewer(tester).onTouchUp!(x, 0.5, false, false, null);
    await tester.pump();
  }

  final controls = find.byTooltip('Settings');

  group('held sideways on an iPhone', () {
    testWidgets('a tap beside the page turns it as a tap at that edge of '
        'the page does, right to left', (tester) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester);
      // The page itself stays clear of both sides.
      expect(
        tester.getRect(viewerFinder()),
        const Rect.fromLTRB(62, 0, 956 - 62, 440),
      );

      await tapPage(tester, 0.98);
      await tapPage(tester, 0.02);
      final atEdges = turns();
      expect(atEdges, ['previous()', 'next()']);
      sent.clear();

      await tester.tapAt(const Offset(956 - 20, 220));
      await tester.pump();
      await tester.tapAt(const Offset(20, 220));
      await tester.pump();
      expect(turns(), atEdges);
      expect(controls, findsNothing);
      await closeReader(tester);
    });

    testWidgets('left to right too', (tester) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester, direction: 'ltr');

      await tester.tapAt(const Offset(956 - 20, 220));
      await tester.pump();
      await tester.tapAt(const Offset(20, 220));
      await tester.pump();
      expect(turns(), ['next()', 'previous()']);
      await closeReader(tester);
    });

    testWidgets('with the controls showing, a tap beside the page turns it as '
        'a tap at that edge of the page does', (tester) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester);
      await tapPage(tester, 0.5);
      expect(controls, findsOneWidget);

      await tapPage(tester, 0.02);
      final atEdge = turns();
      expect(atEdge, ['next()']);
      sent.clear();
      await tester.tapAt(const Offset(20, 220));
      await tester.pump();
      expect(turns(), atEdge);
      expect(controls, findsOneWidget, reason: 'as after the tap on the page');
      await closeReader(tester);
    });

    testWidgets('in scroll view a tap beside the page shows the controls, as '
        'a tap on the page does', (tester) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester, scrollView: true);

      await tester.tapAt(const Offset(956 - 20, 220));
      await tester.pump();
      expect(controls, findsOneWidget);
      expect(turns(), isEmpty);
      await closeReader(tester);
    });

    testWidgets('a tap beside the page while text is selected does nothing, '
        'as on the page', (tester) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester);
      viewer(tester).onSelection!(
        const EpubSelectionData(cfi: 'epubcfi(/6/4!/4/2,/1:0,/1:2)', text: '本'),
      );
      await tester.pump();

      await tapPage(tester, 0.98);
      await tester.tapAt(const Offset(956 - 20, 220));
      await tester.pump();
      expect(turns(), isEmpty);
      expect(controls, findsNothing);
      await closeReader(tester);
    });

    testWidgets('taps, swipes and words on the page still do what they did', (
      tester,
    ) async {
      screen(
        tester,
        platform: TargetPlatform.iOS,
        size: _landscape,
        insets: _landscapeInsets,
      );
      await openReader(tester);

      // A swipe from right to left goes back in a right-to-left book.
      viewer(tester).onTouchDown!(0.8, 0.5, null);
      viewer(tester).onTouchUp!(0.2, 0.5, false, false, null);
      await tester.pump();
      expect(turns(), ['previous()']);

      // A word opens the lookup; with no dictionary loaded it says so.
      viewer(tester).onTouchDown!(0.4, 0.4, null);
      viewer(tester).onWordTapped!('本を読む', 0, 0, '本', 0.4, 0.4);
      await tester.pump();
      expect(find.textContaining('still loading'), findsOneWidget);

      // The middle of the page shows the controls.
      await tapPage(tester, 0.5);
      expect(controls, findsOneWidget);
      expect(turns(), ['previous()']);
      await closeReader(tester);
    });
  });

  testWidgets("iPhone Duo's strip beside the page acts as that edge of it", (
    tester,
  ) async {
    // The outer display: the strip is the only side inset, on the right.
    screen(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(466, 678),
      insets: const FakeViewPadding(right: 84, bottom: 20),
    );
    await openReader(tester);
    expect(
      tester.getRect(viewerFinder()),
      const Rect.fromLTRB(0, 0, 466 - 84, 678),
    );

    await tester.tapAt(const Offset(466 - 30, 400));
    await tester.pump();
    expect(turns(), ['previous()']);
    await closeReader(tester);
  });

  testWidgets('upright on an iPhone the page and its taps are as before', (
    tester,
  ) async {
    screen(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(440, 956),
      insets: const FakeViewPadding(top: 62, bottom: 34),
    );
    await openReader(tester);
    expect(
      tester.getRect(viewerFinder()),
      const Rect.fromLTRB(0, 62, 440, 956),
    );

    // Above the page, beside the Dynamic Island: nothing, as before.
    await tester.tapAt(const Offset(400, 30));
    await tester.pump();
    expect(turns(), isEmpty);
    expect(controls, findsNothing);

    await tapPage(tester, 0.98);
    await tapPage(tester, 0.02);
    expect(turns(), ['previous()', 'next()']);
    await closeReader(tester);
  });

  testWidgets('on Android the page still fills the screen, cutout included', (
    tester,
  ) async {
    screen(
      tester,
      platform: TargetPlatform.android,
      size: _landscape,
      insets: const FakeViewPadding(left: 62, bottom: 20),
    );
    await openReader(tester);
    expect(tester.getRect(viewerFinder()), Offset.zero & _landscape);

    await tapPage(tester, 0.98);
    await tapPage(tester, 0.02);
    expect(turns(), ['previous()', 'next()']);
    await closeReader(tester);
  });
}
