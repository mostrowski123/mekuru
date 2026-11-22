import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_brightness_state.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// A wakelock that is never on and never touches the platform channel.
class NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

/// Brightness notifier fake that never touches the platform channel.
class FakeReaderBrightnessNotifier extends ReaderBrightnessNotifier {
  @override
  ReaderBrightnessState build() => const ReaderBrightnessState();

  @override
  Future<void> applyForReaderOpen() async {}

  @override
  Future<void> resetBrightness() async {}
}

/// Pro-unlock notifier fake with a fixed unlock state.
class FakeProUnlockedNotifier extends ProUnlockedNotifier {
  FakeProUnlockedNotifier(this._unlocked);
  final bool _unlocked;

  @override
  Future<bool> build() async => _unlocked;
}

/// Settings surfaces build rows lazily inside scrollables (the reader sheets
/// are half-height draggable sheets); scroll until [finder] is built and
/// visible before interacting with it.
Future<void> scrollSettingsTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
