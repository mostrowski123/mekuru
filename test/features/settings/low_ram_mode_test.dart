import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/low_ram_mode_prompts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_download_notifiers.dart';
import '../../shared/reader_settings_test_helpers.dart';
import '../../test_app.dart';

const _modeKey = 'app.low_ram_mode';
const _hintKey = 'app.low_ram_hint_shown';
const _hintTitle = 'Turn on Low RAM mode?';

final _modeOn = lowRamModeProvider.overrideWithBuild((ref, notifier) => true);

void main() {
  final logged = <String, Map<String, SentryAttribute>>{};
  var closes = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logged.clear();
    closes = 0;
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logged[message] = attributes;
    GemmaTranslation.debugClose = () async => closes++;
  });

  tearDown(() {
    usageLogSinkOverride = null;
    resetUsageTagsForTest();
    debugDeviceLowOnMemory = null;
    GemmaTranslation.debugClose = null;
  });

  test('both keys round-trip and stay out of backups', () async {
    final storage = SharedPreferencesAppSettingsStorage();
    expect(await storage.loadLowRamMode(), isNull);
    expect(await storage.loadLowRamHintShown(), isNull);

    await storage.saveLowRamMode(true);
    await storage.saveLowRamHintShown(true);
    expect(await storage.loadLowRamMode(), isTrue);
    expect(await storage.loadLowRamHintShown(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_modeKey), isTrue);
    expect(prefs.getBool(_hintKey), isTrue);

    // They describe this device, not the library.
    expect(BackupService.appKeys, isNot(contains(_modeKey)));
    expect(BackupService.appKeys, isNot(contains(_hintKey)));
  });

  test('the first state is the value main preloaded', () async {
    SharedPreferences.setMockInitialValues({_modeKey: true});
    await PreloadedAppSettings.load();
    addTearDown(() => PreloadedAppSettings.initialLowRamMode = false);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(lowRamModeProvider), isTrue);
  });

  group('the hint', () {
    Future<void> offer(WidgetTester tester, {bool modeOn = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [if (modeOn) _modeOn],
          child: buildLocalizedTestApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => offerLowRamMode(context, ref),
                child: const Text('offer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('offer'));
      await tester.pumpAndSettle();
    }

    testWidgets('is offered once, and Turn on turns the mode on', (
      tester,
    ) async {
      debugDeviceLowOnMemory = true;
      await offer(tester);
      expect(find.text(_hintTitle), findsOneWidget);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('offer')),
      );
      expect(container.read(lowRamModeProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_modeKey), isTrue);
      expect(prefs.getBool(_hintKey), isTrue);
      expect(closes, 1);
      final toggled = logged['low_ram_mode.toggled']!;
      expect(toggled['enabled']!.value, true);
      expect(toggled['source']!.value, 'hint');
      expect(toggled['low_ram_mode']!.value, 'true');

      await offer(tester);
      expect(find.text(_hintTitle), findsNothing);
    });

    testWidgets('is not offered again after Not now', (tester) async {
      debugDeviceLowOnMemory = true;
      await offer(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await offer(tester);
      expect(find.text(_hintTitle), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_modeKey), isNull);
    });

    testWidgets('is never offered when the mode is on', (tester) async {
      debugDeviceLowOnMemory = true;
      await offer(tester, modeOn: true);
      expect(find.text(_hintTitle), findsNothing);
    });

    testWidgets('is never offered with more memory', (tester) async {
      debugDeviceLowOnMemory = false;
      await offer(tester);
      expect(find.text(_hintTitle), findsNothing);
    });

    testWidgets('is never offered on iOS', (tester) async {
      debugDeviceLowOnMemory = true;
      await offer(tester);
      expect(find.text(_hintTitle), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_hintKey), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('Settings', () {
    Future<void> pumpSettings(
      WidgetTester tester, {
      bool modeOn = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [if (modeOn) _modeOn],
          child: buildLocalizedTestApp(home: const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the switch turns the mode on', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Low RAM mode'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_modeKey), isTrue);
      expect(logged['low_ram_mode.toggled']!['source']!.value, 'settings');
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Low RAM mode'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('the switch is hidden on iOS', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Low RAM mode'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('turning the mode on hides sentence translation', (
      tester,
    ) async {
      debugGemmaModelOps = (
        installed: () async => false,
        download: (onProgress, _) async {},
        delete: () async {},
        hasFiles: () async => false,
        cancel: () => true,
        pending: () async => false,
      );
      addTearDown(() => debugGemmaModelOps = null);
      await pumpSettings(tester);
      await scrollSettingsTo(tester, find.text('Sentence translation'));
      expect(find.text('Translation model'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      await container.read(lowRamModeProvider.notifier).setLowRamMode(true);
      await tester.pumpAndSettle();
      expect(
        find.text('Sentence translation', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Translation model', skipOffstage: false), findsNothing);
    });
  });

  testWidgets('the mode hides translation and OCR downloads', (tester) async {
    mockWifiConnected(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...fakeDownloadNotifierOverrides([]), _modeOn],
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(find.byType(ListView));
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    expect(children.whereType<LocalOcrDownloadTile>(), isEmpty);
    expect(children.whereType<NdlTextModelDownloadTile>(), isEmpty);
    expect(
      children.map((child) => child.runtimeType.toString()),
      isNot(contains('_SentenceTranslationTile')),
    );
  });
}
