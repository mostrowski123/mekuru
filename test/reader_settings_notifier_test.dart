import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';

class _FakeReaderSettingsStorage implements ReaderSettingsStorage {
  _FakeReaderSettingsStorage({this.initialSettings});

  ReaderSettings? initialSettings;
  ReaderSettings? savedSettings;
  int saveCalls = 0;

  @override
  Future<ReaderSettings?> load() async => initialSettings;

  @override
  Future<void> save(ReaderSettings settings) async {
    saveCalls += 1;
    savedSettings = settings;
  }
}

void main() {
  group('ReaderSettingsNotifier', () {
    test('loads persisted settings correctly', () async {
      final fakeStorage = _FakeReaderSettingsStorage(
        initialSettings: const ReaderSettings(
          fontSize: 24,
          verticalText: false,
          readingDirection: ReaderDirection.ltr,
          pageTurnAnimationEnabled: false,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          readerSettingsStorageProvider.overrideWithValue(fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(readerSettingsProvider.notifier)
          .loadPersistedSettings();
      final settings = container.read(readerSettingsProvider);

      expect(settings.fontSize, 24);
      expect(settings.verticalText, isFalse);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.pageTurnAnimationEnabled, isFalse);
    });

    test('persists updates for all reader settings', () async {
      final fakeStorage = _FakeReaderSettingsStorage();
      final container = ProviderContainer(
        overrides: [
          readerSettingsStorageProvider.overrideWithValue(fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.setFontSize(20);
      notifier.setVerticalText(false);
      notifier.setReadingDirection(ReaderDirection.ltr);
      notifier.setPageTurnAnimationEnabled(false);

      await Future<void>.delayed(Duration.zero);

      expect(fakeStorage.saveCalls, greaterThanOrEqualTo(4));
      expect(fakeStorage.savedSettings, isNotNull);
      expect(fakeStorage.savedSettings!.fontSize, 20);
      expect(fakeStorage.savedSettings!.verticalText, isFalse);
      expect(fakeStorage.savedSettings!.readingDirection, ReaderDirection.ltr);
      expect(fakeStorage.savedSettings!.pageTurnAnimationEnabled, isFalse);
    });

    test(
      'keeps reading direction independent from vertical text setting',
      () async {
        final fakeStorage = _FakeReaderSettingsStorage();
        final container = ProviderContainer(
          overrides: [
            readerSettingsStorageProvider.overrideWithValue(fakeStorage),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(readerSettingsProvider.notifier);
        notifier.setReadingDirection(ReaderDirection.ltr);
        notifier.toggleVerticalText();

        await Future<void>.delayed(Duration.zero);
        final settings = container.read(readerSettingsProvider);

        expect(settings.verticalText, isFalse);
        expect(settings.readingDirection, ReaderDirection.ltr);
      },
    );
  });
}
