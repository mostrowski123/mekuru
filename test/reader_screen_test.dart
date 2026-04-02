import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'test_app.dart';

class _PendingReaderSettingsStorage implements ReaderSettingsStorage {
  final Completer<ReaderSettings?> _loadCompleter =
      Completer<ReaderSettings?>();

  @override
  Future<ReaderSettings?> load() => _loadCompleter.future;

  @override
  Future<void> save(ReaderSettings settings) async {}

  void complete([ReaderSettings? settings]) {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete(settings);
    }
  }
}

class _FakeBrightnessNotifier extends BrightnessNotifier {
  int initializeCalls = 0;
  int resetCalls = 0;

  @override
  double? build() => 0.5;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> resetBrightness() async {
    resetCalls += 1;
  }
}

class _FakeBillingClient extends OcrBillingClient {
  @override
  Future<bool> isRefreshDue() async => false;

  @override
  Future<OcrBillingStatus?> refreshStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    return const OcrBillingStatus(ocrUnlocked: false, creditBalance: 0);
  }

  @override
  void dispose() {}
}

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  bool isEnabled = false;
  int toggleCalls = 0;

  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => isEnabled;

  @override
  Future<void> toggle({required bool enable}) async {
    toggleCalls += 1;
    isEnabled = enable;
  }
}

Book _buildTestBook() {
  return Book(
    id: 1,
    title: 'Regression Test Book',
    filePath: '/tmp/reader-screen-test.epub',
    bookType: 'epub',
    totalPages: 1,
    readProgress: 0,
    dateAdded: DateTime(2026, 3, 31),
  );
}

void main() {
  late WakelockPlusPlatformInterface originalWakelockPlatform;
  late _FakeWakelockPlatform fakeWakelockPlatform;

  setUp(() {
    originalWakelockPlatform = WakelockPlusPlatformInterface.instance;
    fakeWakelockPlatform = _FakeWakelockPlatform();
    WakelockPlusPlatformInterface.instance = fakeWakelockPlatform;
  });

  tearDown(() {
    WakelockPlusPlatformInterface.instance = originalWakelockPlatform;
  });

  testWidgets('ReaderScreen disposes without reading providers after unmount', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final storage = _PendingReaderSettingsStorage();
    final container = ProviderContainer(
      overrides: [
        readerSettingsStorageProvider.overrideWithValue(storage),
        readerBookRepositoryProvider.overrideWithValue(BookRepository(db)),
        brightnessProvider.overrideWith(_FakeBrightnessNotifier.new),
        ocrBillingClientProvider.overrideWithValue(_FakeBillingClient()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: ReaderScreen(book: _buildTestBook()),
        ),
      ),
    );

    final brightnessNotifier =
        container.read(brightnessProvider.notifier) as _FakeBrightnessNotifier;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(brightnessNotifier.resetCalls, 1);

    storage.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(brightnessNotifier.initializeCalls, 0);
    expect(fakeWakelockPlatform.toggleCalls, 1);
    expect(fakeWakelockPlatform.isEnabled, isFalse);
  });
}
