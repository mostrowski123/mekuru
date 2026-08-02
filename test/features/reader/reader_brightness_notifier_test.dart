import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';

class _FakeReaderSettingsStorage implements ReaderSettingsStorage {
  _FakeReaderSettingsStorage({this.initialSettings});

  ReaderSettings? initialSettings;
  ReaderSettings? savedSettings;

  @override
  Future<ReaderSettings?> load() async => initialSettings;

  @override
  Future<void> save(ReaderSettings settings) async {
    savedSettings = settings;
  }
}

ProviderContainer _createContainer(_FakeReaderSettingsStorage storage) {
  final container = ProviderContainer(
    overrides: [readerSettingsStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderBrightnessNotifier', () {
    test('setBrightness persists the override', () async {
      final storage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage);

      await container
          .read(readerBrightnessProvider.notifier)
          .setBrightness(0.3);

      expect(container.read(readerBrightnessProvider).override, 0.3);
      expect(container.read(readerBrightnessProvider).followsSystem, isFalse);
      expect(container.read(readerBrightnessProvider).sliderValue, 0.3);
      expect(storage.savedSettings?.brightness, 0.3);
    });

    test('followSystemBrightness clears the override', () async {
      final storage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage);
      final notifier = container.read(readerBrightnessProvider.notifier);

      await notifier.setBrightness(0.3);
      await notifier.followSystemBrightness();

      final state = container.read(readerBrightnessProvider);
      expect(state.override, isNull);
      expect(state.followsSystem, isTrue);
      expect(storage.savedSettings, isNotNull);
      expect(storage.savedSettings!.brightness, isNull);
    });

    test('resetBrightness does not clear the persisted override', () async {
      // Regression for the old stale-slider bug: leaving the reader resets
      // the OS-level brightness but must not lose the saved preference.
      final storage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage);
      final notifier = container.read(readerBrightnessProvider.notifier);

      await notifier.setBrightness(0.3);
      await notifier.resetBrightness();

      expect(container.read(readerBrightnessProvider).override, 0.3);
      expect(storage.savedSettings?.brightness, 0.3);
    });

    test('override survives an app restart via persisted settings', () async {
      final storage = _FakeReaderSettingsStorage(
        initialSettings: const ReaderSettings(brightness: 0.3),
      );
      final container = _createContainer(storage);

      await container
          .read(readerSettingsProvider.notifier)
          .loadPersistedSettings();

      final state = container.read(readerBrightnessProvider);
      expect(state.override, 0.3);
      expect(state.sliderValue, 0.3);
    });

    test('applyForReaderOpen keeps the override when platform calls fail', () async {
      // No screen_brightness plugin in unit tests: every platform call
      // throws and is swallowed; the state must stay consistent.
      final storage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage);
      final notifier = container.read(readerBrightnessProvider.notifier);

      await notifier.setBrightness(0.3);
      await notifier.applyForReaderOpen();

      final state = container.read(readerBrightnessProvider);
      expect(state.override, 0.3);
      expect(state.systemLevel, 0.5);
    });
  });
}
