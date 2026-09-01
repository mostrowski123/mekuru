import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_settings_screen.dart';
import 'package:mekuru/main.dart';

import 'shared/test_database.dart';

/// Real secure storage is a platform channel, so the client provider's build
/// spans a real async gap. Mirror that, or the build completes in microtasks
/// before autoDispose gets a chance to bite.
class _SlowFakeSecrets extends ServerSecretStorage {
  @override
  Future<String?> load(int connectionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return 'api-key';
  }
}

void main() {
  testWidgets('link existing books holds the autoDispose client provider', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'kavita',
            name: 'Home',
            baseUrl: 'http://127.0.0.1:9',
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          serverSecretStorageProvider.overrideWithValue(_SlowFakeSecrets()),
        ],
        child: const MaterialApp(home: ServerSettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.playlist_add_check));
    // flutter_test answers every HTTP request with 400, so a healthy run
    // fails at the network layer. The regression failed earlier, inside the
    // provider build, because nothing held the autoDispose provider alive.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.textContaining('after it has been disposed'), findsNothing);
    expect(
      find.textContaining(RegExp('Linking failed|No new matches|Linked ')),
      findsOneWidget,
    );

    // Let the snackbar timers expire so the test ends with none pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
