// A manga whose pages cannot be loaded for a reason the reader has no words
// of its own for says only that they could not be loaded. The error goes to
// telemetry, never on screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

void main() {
  final ja = AppLocalizationsJa();
  late WakelockPlusPlatformInterface originalWakelock;
  final logs = <String>[];

  setUp(() {
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = NoWakelock();
    SharedPreferences.setMockInitialValues({});
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });
  tearDown(() {
    WakelockPlusPlatformInterface.instance = originalWakelock;
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
  });

  testWidgets('pages that fail to load for an unexpected reason say they '
      'could not be loaded', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        mangaPagesProvider(1).overrideWith(
          (ref) async => throw StateError('秘密の漫画/pages_cache.json: locked'),
        ),
        ocrProgressProvider(1).overrideWith((ref) => Stream.value(null)),
        readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
        proUnlockedProvider.overrideWith(() => FakeProUnlockedNotifier(false)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: MangaReaderScreen(
            book: Book(
              id: 1,
              isFavorite: false,
              title: 'Manga',
              filePath: '/unused',
              bookType: 'manga',
              totalPages: 1,
              readProgress: 0,
              dateAdded: DateTime(2026, 11, 22),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(ja.mangaReaderFailedToLoad), findsOneWidget);
    expect(find.textContaining(RegExp('秘密|Bad state|locked')), findsNothing);
    expect(find.text(ja.commonLoadFailed), findsOneWidget);
    expect(logs, contains('manga.pages_load_failed'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
