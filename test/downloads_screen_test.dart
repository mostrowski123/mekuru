import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

void main() {
  testWidgets('starter pack starts both downloads together', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(true);
    final started = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(started),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();

    expect(started, unorderedEquals(<String>['jmdict:jmdictEnglish', 'jpdb']));
    final list = tester.widget<ListView>(find.byType(ListView));
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    expect(children.first, isNot(isA<LocalOcrDownloadTile>()));
    expect(children[children.length - 2], isA<LocalOcrDownloadTile>());
  });

  testWidgets('off Wi-Fi the starter pack asks before using mobile data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(false);
    final started = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(started),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();
    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(find.textContaining('about 22 MB'), findsOneWidget);

    await tester.tap(inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(started, isEmpty);

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Download'));
    await tester.pumpAndSettle();
    expect(started, unorderedEquals(<String>['jmdict:jmdictEnglish', 'jpdb']));
  });
}
