import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_browse_screen.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_database.dart';
import 'test_app.dart';

class _FakeSecrets extends ServerSecretStorage {
  @override
  Future<String?> load(int connectionId) async => 'api-key';
}

void main() {
  late AppDatabase db;
  final loggedEvents = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    loggedEvents.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) {
      loggedEvents.add(message);
    };
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    await db.close();
  });

  Future<void> openImportSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          serverSecretStorageProvider.overrideWithValue(_FakeSecrets()),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Unmounts the tree so drift stream subscriptions close, then flushes
  /// their close timers so the binding's timersPending invariant holds.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('import sheet hides servers that are disabled', (tester) async {
    await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'komga',
            name: 'Attic',
            baseUrl: 'http://attic.local',
            enabled: const Value(false),
          ),
        );

    await openImportSheet(tester);

    expect(find.text('Import EPUB'), findsWidgets);
    expect(find.textContaining('Download from'), findsNothing);
    await unmount(tester);
  });

  testWidgets('import sheet row opens the server and logs usage', (
    tester,
  ) async {
    await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'kavita',
            name: 'Home',
            baseUrl: 'http://127.0.0.1:9',
          ),
        );

    await openImportSheet(tester);

    await tester.tap(find.text('Download from Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ServerBrowseScreen), findsOneWidget);
    expect(loggedEvents, contains('library.server_browse_opened'));
    await unmount(tester);
  });
}
