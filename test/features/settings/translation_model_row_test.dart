import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
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
  late Completer<void> downloadDone;
  late void Function(double fraction) report;

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
      download: (onProgress) {
        downloads++;
        report = onProgress;
        // Made here, in the test's zone, so completing it reaches pump().
        downloadDone = Completer<void>();
        return downloadDone.future;
      },
      delete: () async {},
      hasFiles: () async => false,
      cancel: () {
        cancels++;
        return true;
      },
      pending: () async => false,
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
    Locale locale = const Locale('en'),
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(translationModelProvider.notifier).setChoice(choice);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: const SettingsScreen(),
          locale: locale,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollSettingsTo(
      tester,
      find.text(
        lookupAppLocalizations(locale).settingsSentenceTranslationTitle,
      ),
    );
    return container;
  }

  Finder rowSubtitle(String text) => find.descendant(
    of: find.widgetWithText(ListTile, 'Translation model'),
    matching: find.text(text),
  );

  const notDownloaded = 'Not downloaded yet. Tap to download (2.6 GB).';

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
    expect(find.text(notDownloaded), findsOneWidget);
  }, variant: _android);

  testWidgets('the Standard size is for the app language', (tester) async {
    final es = lookupAppLocalizations(const Locale('es'));
    await pumpSettings(tester, locale: const Locale('es'));

    await tester.tap(find.text(es.settingsTranslationModelTitle));
    await tester.pumpAndSettle();

    // Spanish pivots through English: two models.
    expect(
      find.text(es.translationModelStandardOption(size: '91 MB')),
      findsOneWidget,
    );
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

  testWidgets('High quality downloads first and is chosen once it is done', (
    tester,
  ) async {
    debugDeviceLowOnMemory = false;
    mockWifiConnected(false);
    final container = await pumpSettings(tester);

    await pick(tester, 'High quality (2.6 GB)');
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    expect(downloads, 1);
    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
    expect(rowSubtitle('High quality: downloading 0%'), findsOneWidget);
    report(0.45);
    await tester.pump();
    expect(rowSubtitle('High quality: downloading 45%'), findsOneWidget);

    installed = true;
    downloadDone.complete();
    await tester.pumpAndSettle();

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.high,
    );
    expect(rowSubtitle('High quality'), findsOneWidget);
  }, variant: _android);

  testWidgets('while it downloads, High quality shows progress and is off', (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    unawaited(container.read(gemmaDownloadProvider.notifier).start());
    await tester.pump();
    report(0.42);

    await pick(tester, 'High quality (2.6 GB)');

    // The sheet is still up and nothing changed.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('High quality: downloading 42%'),
      ),
      findsOneWidget,
    );
    expect(find.text('Standard (55 MB)'), findsOneWidget);
    expect(downloads, 1);
    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
  }, variant: _android);

  testWidgets('an installed model is chosen without downloading', (
    tester,
  ) async {
    installed = true;
    debugDeviceLowOnMemory = true;
    mockWifiConnected(false);
    final container = await pumpSettings(tester);

    await tester.tap(find.text('Translation model'));
    await tester.pumpAndSettle();
    expect(find.text(notDownloaded), findsNothing);
    await tester.tap(find.text('High quality (2.6 GB)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

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
    installed = true;
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
    installed = true;
    final container = await pumpSettings(
      tester,
      choice: TranslationModelChoice.high,
    );
    expect(rowSubtitle('High quality'), findsOneWidget);

    await pick(tester, 'Standard (55 MB)');

    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );
    expect(closes, 1);
  }, variant: _android);

  testWidgets('tapping the checked Standard leaves a download running', (
    tester,
  ) async {
    debugDeviceLowOnMemory = false;
    mockWifiConnected(false);
    final container = await pumpSettings(tester);
    await pick(tester, 'High quality (2.6 GB)');
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();
    expect(downloads, 1);

    await pick(tester, 'Standard (55 MB)');

    expect(cancels, 0);
    expect(closes, 0);
    expect(container.read(gemmaDownloadProvider), isA<GemmaDownloading>());
  }, variant: _android);

  testWidgets('"Use Standard" stops a running download', (tester) async {
    debugDeviceLowOnMemory = true;
    final container = await pumpSettings(tester);
    await pick(tester, 'High quality (2.6 GB)');
    // A download that started while the dialog was up.
    unawaited(container.read(gemmaDownloadProvider.notifier).start());
    await tester.pump();

    await tester.tap(find.text('Use Standard'));
    await tester.pumpAndSettle();

    expect(cancels, 1);
  }, variant: _android);

  testWidgets("opening the picker keeps a failed download's error", (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    unawaited(container.read(gemmaDownloadProvider.notifier).start());
    await tester.pump();
    downloadDone.completeError(Exception('offline'));
    await tester.pump();
    expect(container.read(gemmaDownloadProvider), isA<GemmaDownloadFailed>());

    await tester.tap(find.text('Translation model'));
    await tester.pumpAndSettle();

    expect(container.read(gemmaDownloadProvider), isA<GemmaDownloadFailed>());
  }, variant: _android);

  testWidgets('a double tap opens one picker', (tester) async {
    await pumpSettings(tester);
    // The disk check before the sheet is still running at the second tap.
    final check = Completer<bool>();
    debugGemmaModelOps = (
      installed: () => check.future,
      download: (_) async {},
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => false,
      pending: () async => false,
    );

    await tester.tap(find.text('Translation model'));
    await tester.pump();
    await tester.tap(find.text('Translation model'));
    check.complete(false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
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
