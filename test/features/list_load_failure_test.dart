import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_attributions.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/load_failed_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/test_database.dart';
import '../test_app.dart';

/// How a damaged database answers a read.
Exception _malformed() => Exception(
  'SqliteException(11): database disk image is malformed, path: /data/秘密',
);

class _ApplyFails extends PendingDictionaryRestoreService {
  @override
  applyPendingRestore(repository) async => throw _malformed();
}

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  final logs = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: buildLocalizedTestApp(locale: const Locale('ja'), home: home),
      ),
    );
    // Riverpod tries a failed stream again for about a minute first.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
  }

  void expectWorded() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('malformed'), findsNothing);
    expect(find.textContaining('Unable to load'), findsNothing);
    expect(find.text(ja.commonLoadFailed), findsOneWidget);
  }

  testWidgets('the server list that cannot load says so in Japanese', (
    tester,
  ) async {
    await pump(
      tester,
      const ServerSettingsScreen(),
      overrides: [
        serverConnectionsProvider.overrideWith(
          (ref) => Stream.error(_malformed()),
        ),
      ],
    );

    expectWorded();
    expect(logs, contains('sync.connections_load_failed'));
  });

  group('the dictionary manager', () {
    List<Override> overrides({
      required Stream<List<DictionaryMeta>> Function() dictionaries,
      PendingDictionaryRestoreService? restore,
    }) => [
      dictionaryRepositoryProvider.overrideWithValue(DictionaryRepository(db)),
      dictionariesProvider.overrideWith((ref) => dictionaries()),
      pendingDictionaryRestorePreviewProvider.overrideWith(
        (ref) async => const PendingDictionaryRestorePreview(
          totalCount: 1,
          matchingCount: 1,
          missingCount: 0,
        ),
      ),
      if (restore != null)
        pendingDictionaryRestoreServiceProvider.overrideWithValue(restore),
    ];

    testWidgets('whose list cannot load says so in Japanese', (tester) async {
      await pump(
        tester,
        const DictionaryManagerScreen(),
        overrides: overrides(dictionaries: () => Stream.error(_malformed())),
      );

      expectWorded();
      expect(logs, contains('dictionary.manager_load_failed'));
    });

    testWidgets('says so when the backup settings cannot be applied', (
      tester,
    ) async {
      await pump(
        tester,
        const DictionaryManagerScreen(),
        overrides: overrides(
          dictionaries: () => Stream.value([
            DictionaryMeta(
              id: 1,
              name: 'JMdict',
              isEnabled: true,
              dateImported: DateTime(2026, 3, 12),
              sortOrder: 0,
              isHidden: false,
            ),
          ]),
          restore: _ApplyFails(),
        ),
      );

      await tester.tap(find.text(ja.dictionaryManagerPendingBackupApplyButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(ja.dictionaryManagerPendingBackupApplyButton).last,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('malformed'), findsNothing);
      expect(
        find.text(ja.dictionaryManagerPendingBackupFailed),
        findsOneWidget,
      );
      expect(logs, contains('dictionary.pending_restore_failed'));
    });
  });

  testWidgets('an OCR licence that cannot load says so in Japanese', (
    tester,
  ) async {
    // The first licence cannot be read, once its tile is open: the screen asks
    // for every licence when it builds, and a failure no tile listens to yet
    // goes unheard. The others answer.
    final opened = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (key) async {
        if (!utf8.decode(key!.buffer.asUint8List()).contains('MANGA-OCR')) {
          return ByteData.sublistView(utf8.encode('licence'));
        }
        await opened.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('ja'),
        home: const OcrLicenseScreen(),
      ),
    );

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pump();
    opened.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expectWorded();
    expect(logs, contains('settings.ocr_licence_load_failed'));
  });

  testWidgets('LoadFailedText logs its error once, however often it builds', (
    tester,
  ) async {
    final error = _malformed();
    Widget page(Color color) => buildLocalizedTestApp(
      locale: const Locale('ja'),
      home: ColoredBox(
        color: color,
        child: LoadFailedText(error, event: 'test.load_failed'),
      ),
    );
    await tester.pumpWidget(page(Colors.white));
    await tester.pumpWidget(page(Colors.black));

    expect(find.text(ja.commonLoadFailed), findsOneWidget);
    expect(logs.where((log) => log == 'test.load_failed'), hasLength(1));
  });
}
