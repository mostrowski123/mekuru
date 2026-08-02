import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_reader_settings_sheet.dart';
import 'package:mekuru/features/reader/data/models/reader_brightness_state.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

class _FakeBrightnessNotifier extends ReaderBrightnessNotifier {
  @override
  ReaderBrightnessState build() => const ReaderBrightnessState();

  @override
  Future<void> applyForReaderOpen() async {}

  @override
  Future<void> resetBrightness() async {}
}

class _FakeProUnlocked extends ProUnlockedNotifier {
  _FakeProUnlocked(this._unlocked);
  final bool _unlocked;

  @override
  Future<bool> build() async => _unlocked;
}

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  bool proUnlocked = true,
  void Function(String, Object)? onSettingChanged,
  ValueChanged<bool>? onAutoCropToggled,
}) async {
  final container = ProviderContainer(
    overrides: [
      readerBrightnessProvider.overrideWith(_FakeBrightnessNotifier.new),
      proUnlockedProvider.overrideWith(() => _FakeProUnlocked(proUnlocked)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(
        home: Scaffold(
          body: MangaReaderSettingsSheet(
            hasComputedAutoCrop: false,
            onAutoCropToggled: onAutoCropToggled ?? (_) {},
            onAutoCropRerun: () {},
            onUnlockPro: () {},
            onSettingChanged: onSettingChanged ?? (_, _) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The sheet's ListView builds rows lazily inside a half-height draggable
/// sheet; scroll until [finder] is built and visible before interacting.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('reading direction is a segmented control', (tester) async {
    final container = await _pumpSheet(tester);
    await _scrollTo(tester, find.byType(SegmentedButton<ReaderDirection>));

    await tester.tap(find.text('Left to Right'));
    await tester.pumpAndSettle();

    expect(
      container.read(readerSettingsProvider).mangaReadingDirection,
      ReaderDirection.ltr,
    );
  });

  testWidgets('toggling the debug overlay does not close the sheet', (
    tester,
  ) async {
    final container = await _pumpSheet(tester);
    final debugFinder = find.widgetWithText(
      SettingsSwitchRow,
      'Debug Word Overlay',
    );
    await _scrollTo(tester, debugFinder);
    await tester.tap(debugFinder);
    await tester.pumpAndSettle();

    // The sheet content is still mounted and the provider was updated.
    expect(find.byType(MangaReaderSettingsSheet), findsOneWidget);
    expect(container.read(mangaDebugWordOverlayProvider), isTrue);
  });

  testWidgets('non-Pro users see a disabled auto-crop tile with Unlock', (
    tester,
  ) async {
    await _pumpSheet(tester, proUnlocked: false);
    await _scrollTo(tester, find.text('Unlock'));
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.widgetWithText(SettingsSwitchRow, 'Auto-Crop'), findsNothing);
  });

  testWidgets('view mode change fires telemetry', (tester) async {
    final changes = <String>[];
    await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );
    await _scrollTo(tester, find.byType(SegmentedButton<MangaViewMode>));
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    expect(changes, contains('view_mode'));
  });
}
