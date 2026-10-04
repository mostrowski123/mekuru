import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../test_app.dart';

void main() {
  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Scaffold(body: MangaOcrIosDownloadTile()),
      ),
    );
    // The installed check is real file I/O, which the fake clock never runs.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  // The tile spins while the dialog is open, so it never settles there.
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder inDialog(Finder text) =>
      find.descendant(of: find.byType(AlertDialog), matching: text);

  testWidgets('offers the optional manga-ocr pack with its size', (
    tester,
  ) async {
    await pumpTile(tester);

    expect(find.text('Download'), findsOneWidget);
    // Encoder, decoder and vocabulary, without Android's detector.
    expect(find.textContaining('201.5 MB'), findsOneWidget);
    expect(find.textContaining('Optional'), findsOneWidget);
  });

  testWidgets('off Wi-Fi asks before downloading the pack', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockWifiConnected(false);
      await pumpTile(tester);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      expect(find.text('Download over mobile data?'), findsOneWidget);
      expect(inDialog(find.textContaining('201.5 MB')), findsOneWidget);
      // Busy while asking: no second tap can start a second download.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Download'),
        ),
        findsNothing,
      );

      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      await tester.tap(inDialog(find.text('Download')));
      await pumpDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on Wi-Fi the pack downloads without asking', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockWifiConnected(true);
      await pumpTile(tester);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
