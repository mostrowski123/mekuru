// Reading-mode changes rebuild the viewer, and each new viewer opens at the
// page the last one reported. Walks page view -> scroll view -> page view and
// vertical text -> horizontal -> vertical, several times over, and expects
// every new viewer to show that page, with no script error in the page.
// Android lays each new WebView out at 0 x 0 and gives it its size while the
// book opens; that resize used to clear the page being opened (a blank page,
// or a script error and the load timeout).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart'
    show expectPageShown, openReader, writeScrollViewEpub;
import 'test_helpers.dart';

const _title = '表示切り替えの連続';
const _rounds = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_rebuild_chain_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('every viewer a mode change rebuilds shows the page', (
    tester,
  ) async {
    // The page's console reaches the test through debugPrint.
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logged.add(message);
      original(message, wrapWidth: wrapWidth);
    };
    addTearDown(() => debugPrint = original);

    final l10n = await loadExpectedL10n();
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    final viewer = find.byType(CustomEpubViewer);
    final overlay = find.byKey(const Key('reader-loading-overlay'));
    final timedOut = find.text(l10n.readerLoadTimeout);
    final settings = ProviderScope.containerOf(
      tester.element(viewer),
    ).read(readerSettingsProvider.notifier);
    CustomEpubViewer? shown() =>
        tester.widgetList<CustomEpubViewer>(viewer).firstOrNull;

    // Two pages in, so the viewers open somewhere other than the start.
    for (var turn = 0; turn < 2; turn++) {
      controller.next();
      await tester.pump(const Duration(milliseconds: 800));
    }

    Future<void> change(String label, void Function() apply) async {
      final before = shown()!.key;
      final from = logged.length;
      apply();
      for (var tick = 0; tick < 40 && shown()?.key == before; tick++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(shown()?.key, isNot(before), reason: '$label: no new viewer');
      final cfi = shown()!.initialCfi;
      for (var tick = 0; tick < 100 && overlay.evaluate().isNotEmpty; tick++) {
        await tester.pump(const Duration(milliseconds: 250));
        expect(timedOut, findsNothing, reason: '$label: the book never showed');
      }
      expect(overlay, findsNothing, reason: '$label: still loading');
      // The reported location arrives a frame after the page shows.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        logged.skip(from).where((line) => line.contains('Uncaught')),
        isEmpty,
        reason: '$label: the page threw',
      );
      expect(cfi, startsWith('epubcfi('), reason: '$label: opened at no page');
      await expectPageShown(controller, cfi: cfi, reason: label);
    }

    for (var round = 1; round <= _rounds; round++) {
      await change('scroll view $round', () => settings.setScrollView(true));
      await change('page view $round', () => settings.setScrollView(false));
    }
    for (var round = 1; round <= _rounds; round++) {
      await change('horizontal $round', () => settings.setVerticalText(false));
      await change('vertical $round', () => settings.setVerticalText(true));
    }
  });
}
