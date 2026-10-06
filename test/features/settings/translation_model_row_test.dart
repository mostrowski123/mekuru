import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_download_notifiers.dart';
import '../../shared/reader_settings_test_helpers.dart';
import '../../test_app.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  var installed = false;
  var installedChecks = 0;
  var downloads = 0;
  var closes = 0;
  var cancels = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installed = false;
    installedChecks = 0;
    downloads = 0;
    closes = 0;
    cancels = 0;
    debugGemmaModelOps = (
      installed: () async {
        installedChecks++;
        return installed;
      },
      // Never finishes, so the row stays on "downloading".
      download: (_) {
        downloads++;
        return Completer<void>().future;
      },
      delete: () async {},
      hasFiles: () async => false,
      cancel: () {
        cancels++;
        return true;
      },
    );
    GemmaTranslation.debugClose = () async => closes++;
  });

  tearDown(() {
    debugGemmaModelOps = null;
    debugDeviceLowOnMemory = null;
    GemmaTranslation.debugClose = null;
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    TranslationModelChoice choice = TranslationModelChoice.standard,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(translationModelProvider.notifier).setChoice(choice);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, find.text('Sentence translation'));
    return container;
  }

  Finder rowSubtitle(String text) => find.descendant(
    of: find.widgetWithText(ListTile, 'Translation model'),
    matching: find.text(text),
  );

  Future<void> pick(WidgetTester tester, String option) async {
    await tester.tap(find.text('Translation model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  testWidgets('shows Standard and offers both models with their sizes', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(rowSubtitle('Standard'), findsOneWidget);

    await tester.tap(find.text('Translation model'));
    await tester.pumpAndSettle();
    expect(find.text('Standard (55 MB)'), findsOneWidget);
    expect(find.text('High quality (2.6 GB)'), findsOneWidget);
  }, variant: _android);

  testWidgets('"Use Standard" on a low-memory phone keeps Standard', (
    tester,
  ) async {
    debugDeviceLowOnMemory = true;
    final container = await pumpSettings(tester);

    await pick(tester, 'High quality (2.6 GB)');
    expect(find.text('Use Standard'), findsOneWidget);
    await tester.tap(find.text('Use Standard'));
    await tester.pumpAndSettle();

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
    expect(downloads, 0);
    expect(rowSubtitle('Standard'), findsOneWidget);
  }, variant: _android);

  testWidgets('High quality with enough memory starts the download', (
    tester,
  ) async {
    debugDeviceLowOnMemory = false;
    mockWifiConnected(false);
    final container = await pumpSettings(tester);

    await pick(tester, 'High quality (2.6 GB)');
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.high,
    );
    expect(downloads, 1);
    expect(rowSubtitle('High quality: downloading 0%'), findsOneWidget);
  }, variant: _android);

  testWidgets('an installed model is reused without asking', (tester) async {
    installed = true;
    debugDeviceLowOnMemory = false;
    mockWifiConnected(false);
    final container = await pumpSettings(tester);

    await pick(tester, 'High quality (2.6 GB)');

    expect(find.text('Download over mobile data?'), findsNothing);
    expect(downloads, 0);
    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.high,
    );
    expect(rowSubtitle('High quality'), findsOneWidget);
  }, variant: _android);

  testWidgets('"Use Standard" switches an existing High choice to Standard', (
    tester,
  ) async {
    debugDeviceLowOnMemory = true;
    final container = await pumpSettings(
      tester,
      choice: TranslationModelChoice.high,
    );

    await pick(tester, 'High quality (2.6 GB)');
    await tester.tap(find.text('Use Standard'));
    await tester.pumpAndSettle();

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
    expect(closes, 1);
    expect(downloads, 0);
  }, variant: _android);

  testWidgets('picking Standard again closes Gemma', (tester) async {
    final container = await pumpSettings(
      tester,
      choice: TranslationModelChoice.high,
    );
    expect(
      rowSubtitle('High quality: tap to download (2.6 GB)'),
      findsOneWidget,
    );

    await pick(tester, 'Standard (55 MB)');

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
    expect(closes, 1);
  }, variant: _android);

  testWidgets('picking Standard mid-download stops the download', (
    tester,
  ) async {
    final container = await pumpSettings(
      tester,
      choice: TranslationModelChoice.high,
    );
    unawaited(container.read(gemmaDownloadProvider.notifier).start());
    await tester.pumpAndSettle();
    expect(rowSubtitle('High quality: downloading 0%'), findsOneWidget);

    await pick(tester, 'Standard (55 MB)');

    expect(cancels, 1);
    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
  }, variant: _android);

  testWidgets('the row is absent on iOS and Gemma is never checked', (
    tester,
  ) async {
    // On High the row would check the model if it were built.
    await pumpSettings(tester, choice: TranslationModelChoice.high);
    expect(find.text('Translation model'), findsNothing);
    expect(installedChecks, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
