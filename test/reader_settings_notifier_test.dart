import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
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

/// Spy BookRepository that records per-book override writes.
class _SpyBookRepository extends BookRepository {
  _SpyBookRepository(super.db);

  bool? lastVerticalText;
  String? lastReadingDirection;
  int? lastBookId;
  int updateDisplayOverridesCalls = 0;

  @override
  Future<void> updateDisplayOverrides(
    int bookId, {
    required bool? verticalText,
    required String? readingDirection,
  }) async {
    updateDisplayOverridesCalls += 1;
    lastBookId = bookId;
    lastVerticalText = verticalText;
    lastReadingDirection = readingDirection;
    // Do not call super because these tests only need the write intent.
  }
}

class _ReaderSettingsTestHarness {
  _ReaderSettingsTestHarness({required this.container, this.db});

  final ProviderContainer container;
  final AppDatabase? db;

  Future<void> dispose() async {
    container.dispose();
    await db?.close();
  }
}

_ReaderSettingsTestHarness _createHarness({
  _FakeReaderSettingsStorage? storage,
  _SpyBookRepository? bookRepo,
}) {
  final fakeStorage = storage ?? _FakeReaderSettingsStorage();
  final db = bookRepo == null ? AppDatabase(NativeDatabase.memory()) : null;
  final repo = bookRepo ?? _SpyBookRepository(db!);

  final container = ProviderContainer(
    overrides: [
      readerSettingsStorageProvider.overrideWithValue(fakeStorage),
      readerBookRepositoryProvider.overrideWithValue(repo),
    ],
  );

  return _ReaderSettingsTestHarness(container: container, db: db);
}

void main() {
  group('ReaderSettingsNotifier', () {
    test('loads persisted settings correctly', () async {
      final fakeStorage = _FakeReaderSettingsStorage(
        initialSettings: const ReaderSettings(
          fontSize: 24,
          pageTurnAnimationEnabled: false,
        ),
      );

      final harness = _createHarness(storage: fakeStorage);
      addTearDown(harness.dispose);
      final container = harness.container;

      await container
          .read(readerSettingsProvider.notifier)
          .loadPersistedSettings();
      final settings = container.read(readerSettingsProvider);

      expect(settings.fontSize, 24);
      expect(settings.verticalText, isTrue);
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.pageTurnAnimationEnabled, isFalse);
    });

    test('persists updates for global reader settings', () async {
      final fakeStorage = _FakeReaderSettingsStorage();
      final harness = _createHarness(storage: fakeStorage);
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.setFontSize(20);
      notifier.setPageTurnAnimationEnabled(false);

      await Future<void>.delayed(Duration.zero);

      expect(fakeStorage.saveCalls, greaterThanOrEqualTo(2));
      expect(fakeStorage.savedSettings, isNotNull);
      expect(fakeStorage.savedSettings!.fontSize, 20);
      expect(fakeStorage.savedSettings!.pageTurnAnimationEnabled, isFalse);
    });

    test(
      'keeps reading direction independent from vertical text setting',
      () async {
        final fakeStorage = _FakeReaderSettingsStorage();
        final harness = _createHarness(storage: fakeStorage);
        addTearDown(harness.dispose);
        final container = harness.container;

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

  group('ReaderSettingsNotifier - applyBookDefaults', () {
    test('sets RTL and vertical for Japanese book', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'ja');

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.verticalText, isTrue);
    });

    test('sets LTR and horizontal for English book', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'en');

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.verticalText, isFalse);
    });

    test('sets RTL and vertical for null language (legacy books)', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1);

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.verticalText, isTrue);
    });

    test('does not persist global settings (no save calls)', () async {
      final fakeStorage = _FakeReaderSettingsStorage();
      final harness = _createHarness(storage: fakeStorage);
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'en');

      await Future<void>.delayed(Duration.zero);
      expect(fakeStorage.saveCalls, 0);
    });

    test('respects page-progression-direction override', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(
        bookId: 1,
        language: 'ja',
        pageProgressionDirection: 'ltr',
      );

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.verticalText, isFalse);
    });

    test(
      'uses primaryWritingMode to determine vertical text independently of ppd',
      () {
        final harness = _createHarness();
        addTearDown(harness.dispose);
        final container = harness.container;

        final notifier = container.read(readerSettingsProvider.notifier);
        notifier.applyBookDefaults(
          bookId: 1,
          language: 'ja',
          pageProgressionDirection: 'rtl',
          primaryWritingMode: 'horizontal-tb',
        );

        final settings = container.read(readerSettingsProvider);
        expect(settings.readingDirection, ReaderDirection.rtl);
        expect(settings.verticalText, isFalse);
      },
    );

    test('preserves other settings when applying book defaults', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.setFontSize(24);
      notifier.setColorMode(ColorMode.dark);
      notifier.applyBookDefaults(bookId: 1, language: 'en');

      final settings = container.read(readerSettingsProvider);
      expect(settings.fontSize, 24);
      expect(settings.colorMode, ColorMode.dark);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.verticalText, isFalse);
    });
  });

  group('ReaderSettingsNotifier - per-book overrides', () {
    test('uses per-book vertical text override when provided', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(
        bookId: 42,
        language: 'ja',
        overrideVerticalText: false,
        overrideReadingDirection: 'ltr',
      );

      final settings = container.read(readerSettingsProvider);
      expect(settings.verticalText, isFalse);
      expect(settings.readingDirection, ReaderDirection.ltr);
    });

    test('falls back to book defaults when no override is stored', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 42, language: 'ja');

      final settings = container.read(readerSettingsProvider);
      expect(settings.verticalText, isTrue);
      expect(settings.readingDirection, ReaderDirection.rtl);
    });

    test('persists per-book override when verticalText is changed', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final spyRepo = _SpyBookRepository(db);
      final harness = _createHarness(bookRepo: spyRepo);
      addTearDown(() async {
        await harness.dispose();
        await db.close();
      });

      final notifier = harness.container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 42, language: 'ja');
      notifier.setVerticalText(false);

      await Future<void>.delayed(Duration.zero);

      expect(spyRepo.updateDisplayOverridesCalls, 1);
      expect(spyRepo.lastBookId, 42);
      expect(spyRepo.lastVerticalText, isFalse);
    });

    test(
      'persists per-book override when readingDirection is changed',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final spyRepo = _SpyBookRepository(db);
        final harness = _createHarness(bookRepo: spyRepo);
        addTearDown(() async {
          await harness.dispose();
          await db.close();
        });

        final notifier = harness.container.read(
          readerSettingsProvider.notifier,
        );
        notifier.applyBookDefaults(bookId: 42, language: 'ja');
        notifier.setReadingDirection(ReaderDirection.ltr);

        await Future<void>.delayed(Duration.zero);

        expect(spyRepo.updateDisplayOverridesCalls, 1);
        expect(spyRepo.lastBookId, 42);
        expect(spyRepo.lastReadingDirection, 'ltr');
      },
    );

    test('does not persist per-book override when no book is open', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final spyRepo = _SpyBookRepository(db);
      final harness = _createHarness(bookRepo: spyRepo);
      addTearDown(() async {
        await harness.dispose();
        await db.close();
      });

      final notifier = harness.container.read(readerSettingsProvider.notifier);
      notifier.setVerticalText(false);

      await Future<void>.delayed(Duration.zero);

      expect(spyRepo.updateDisplayOverridesCalls, 0);
    });

    test('per-book override is remembered on simulated reopen', () {
      final harness = _createHarness();
      addTearDown(harness.dispose);
      final container = harness.container;

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 42, language: 'ja');
      notifier.setVerticalText(false);
      expect(container.read(readerSettingsProvider).verticalText, isFalse);

      notifier.applyBookDefaults(
        bookId: 42,
        language: 'ja',
        overrideVerticalText: false,
        overrideReadingDirection: 'ltr',
      );

      final settings = container.read(readerSettingsProvider);
      expect(settings.verticalText, isFalse);
      expect(settings.readingDirection, ReaderDirection.ltr);
    });
  });
}
