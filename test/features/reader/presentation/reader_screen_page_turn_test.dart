// A tap or a swipe turns the EPUB page at once, with Animations on or off:
// the page is sent next() or previous() straight away, and no picture of the
// page is taken first.

import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import 'recording_reader.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late List<String> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('reader_page_turn_');
    db = createTestDatabase();
    final webView = RecordingWebViewPlatform();
    InAppWebViewPlatform.instance = webView;
    sent = webView.sent;
  });

  tearDown(() async {
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  /// A touch on the page as the bridge reports it, from [fromX] to [toX]
  /// across the page: a tap when they are the same.
  Future<void> touch(WidgetTester tester, double fromX, double toX) async {
    final viewer = readerViewer(tester);
    viewer.onTouchDown!(fromX, 0.5, null);
    viewer.onTouchUp!(toX, 0.5, false, false, null);
    await tester.pump();
  }

  for (final animations in [true, false]) {
    final label = animations ? 'Animations on' : 'Animations off';

    // A Japanese book reads right to left: forward is the left edge, and a
    // swipe from left to right.
    testWidgets('$label: a tap at an edge turns the page at once', (
      tester,
    ) async {
      await openRecordedReader(
        tester,
        db: db,
        book: recordedBook(tempDir),
        settings: ReaderSettings(readerAnimations: animations),
      );
      sent.clear();
      final idle = tester.binding.transientCallbackCount;

      await touch(tester, 0.02, 0.02);
      expect(sent, ['next()']);
      await touch(tester, 0.98, 0.98);
      expect(sent, ['next()', 'previous()']);
      expect(
        tester.binding.transientCallbackCount,
        idle,
        reason: 'nothing moves',
      );
      await closeRecordedReader(tester);
    });

    testWidgets('$label: a swipe turns the page at once', (tester) async {
      await openRecordedReader(
        tester,
        db: db,
        book: recordedBook(tempDir),
        settings: ReaderSettings(readerAnimations: animations),
      );
      sent.clear();
      final idle = tester.binding.transientCallbackCount;

      await touch(tester, 0.2, 0.8);
      expect(sent, ['next()']);
      await touch(tester, 0.8, 0.2);
      expect(sent, ['next()', 'previous()']);
      expect(
        tester.binding.transientCallbackCount,
        idle,
        reason: 'nothing moves',
      );
      await closeRecordedReader(tester);
    });
  }
}
