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
    // Don't call super — we don't need real DB writes in these tests.
  }
}

ProviderContainer _createContainer({
  _FakeReaderSettingsStorage? storage,
  _SpyBookRepository? bookRepo,
}) {
  final fakeStorage = storage ?? _FakeReaderSettingsStorage();
  final db = AppDatabase(NativeDatabase.memory());
  final repo = bookRepo ?? _SpyBookRepository(db);
  final container = ProviderContainer(
    overrides: [
      readerSettingsStorageProvider.overrideWithValue(fakeStorage),
      readerBookRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return container;
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

      final container = _createContainer(storage: fakeStorage);
      addTearDown(container.dispose);

      await container
          .read(readerSettingsProvider.notifier)
          .loadPersistedSettings();
      final settings = container.read(readerSettingsProvider);

      expect(settings.fontSize, 24);
      // verticalText and readingDirection are per-book, not loaded from global.
      expect(settings.verticalText, isTrue); // class default
      expect(settings.readingDirection, ReaderDirection.rtl); // class default
      expect(settings.pageTurnAnimationEnabled, isFalse);
    });

    test('persists updates for global reader settings', () async {
      final fakeStorage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage: fakeStorage);
      addTearDown(container.dispose);

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
        final container = _createContainer(storage: fakeStorage);
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

  group('ReaderSettingsNotifier — applyBookDefaults', () {
    test('sets RTL and vertical for Japanese book', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'ja');

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.verticalText, isTrue);
    });

    test('sets LTR and horizontal for English book', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'en');

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.verticalText, isFalse);
    });

    test('sets RTL and vertical for null language (legacy books)', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1);

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.verticalText, isTrue);
    });

    test('does NOT persist global settings (no save calls)', () async {
      final fakeStorage = _FakeReaderSettingsStorage();
      final container = _createContainer(storage: fakeStorage);
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 1, language: 'en');

      await Future<void>.delayed(Duration.zero);
      expect(fakeStorage.saveCalls, 0);
    });

    test('respects page-progression-direction override', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      // Japanese book with explicit LTR ppd
      notifier.applyBookDefaults(
        bookId: 1,
        language: 'ja',
        pageProgressionDirection: 'ltr',
      );

      final settings = container.read(readerSettingsProvider);
      expect(settings.readingDirection, ReaderDirection.ltr);
      expect(settings.verticalText, isFalse);
    });

    test('uses primaryWritingMode to determine vertical text independently of ppd', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      // Japanese book with RTL ppd but horizontal writing mode
      notifier.applyBookDefaults(
        bookId: 1,
        language: 'ja',
        pageProgressionDirection: 'rtl',
        primaryWritingMode: 'horizontal-tb',
      );

      final settings = container.read(readerSettingsProvider);
      // Direction follows ppd (RTL), but vertical text follows writing mode
      expect(settings.readingDirection, ReaderDirection.rtl);
      expect(settings.verticalText, isFalse);
    });

    test('preserves other settings when applying book defaults', () {
      final container = _createContainer();
      addTearDown(container.dispose);

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

  group('ReaderSettingsNotifier — per-book overrides', () {
    test('uses per-book vertical text override when provided', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      // Japanese book, but user previously toggled to horizontal
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
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);
      // Japanese book with no overrides (null)
      notifier.applyBookDefaults(bookId: 42, language: 'ja');

      final settings = container.read(readerSettingsProvider);
      expect(settings.verticalText, isTrue);
      expect(settings.readingDirection, ReaderDirection.rtl);
    });

    test('persists per-book override when verticalText is changed', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final spyRepo = _SpyBookRepository(db);
      final container = _createContainer(bookRepo: spyRepo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 42, language: 'ja');
      notifier.setVerticalText(false);

      await Future<void>.delayed(Duration.zero);

      expect(spyRepo.updateDisplayOverridesCalls, 1);
      expect(spyRepo.lastBookId, 42);
      expect(spyRepo.lastVerticalText, isFalse);
    });

    test('persists per-book override when readingDirection is changed',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final spyRepo = _SpyBookRepository(db);
      final container = _createContainer(bookRepo: spyRepo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final notifier = container.read(readerSettingsProvider.notifier);
      notifier.applyBookDefaults(bookId: 42, language: 'ja');
      notifier.setReadingDirection(ReaderDirection.ltr);

      await Future<void>.delayed(Duration.zero);

      expect(spyRepo.updateDisplayOverridesCalls, 1);
      expect(spyRepo.lastBookId, 42);
      expect(spyRepo.lastReadingDirection, 'ltr');
    });

    test('does NOT persist per-book override when no book is open', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final spyRepo = _SpyBookRepository(db);
      final container = _createContainer(bookRepo: spyRepo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final notifier = container.read(readerSettingsProvider.notifier);
      // No applyBookDefaults call — no book is open
      notifier.setVerticalText(false);

      await Future<void>.delayed(Duration.zero);

      expect(spyRepo.updateDisplayOverridesCalls, 0);
    });

    test('per-book override is remembered on simulated reopen', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(readerSettingsProvider.notifier);

      // First open: user changes Japanese book to horizontal
      notifier.applyBookDefaults(bookId: 42, language: 'ja');
      notifier.setVerticalText(false);
      expect(container.read(readerSettingsProvider).verticalText, isFalse);

      // Simulate reopening the same book with the saved override
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
