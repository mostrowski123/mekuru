import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_browse_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;

import '../../shared/test_database.dart';
import '../../test_app.dart';

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() {
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  /// Opens browsing on a server whose client cannot be made: [failure].
  Future<void> browse(WidgetTester tester, Object failure) async {
    final connection = (await tester.runAsync(() async {
      final id = await db
          .into(db.serverConnections)
          .insert(
            ServerConnectionsCompanion.insert(
              serverType: 'komga',
              name: '家のサーバー',
              baseUrl: 'https://komga.example.com',
            ),
          );
      return (db.select(
        db.serverConnections,
      )..where((t) => t.id.equals(id))).getSingle();
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          serverClientProvider(
            connection.id,
          ).overrideWith((ref) => Future<ServerClient>.error(failure)),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: ServerBrowseScreen(connection: connection),
        ),
      ),
    );
    // Riverpod tries a failed provider again for about a minute first.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
  }

  List<Map<String, SentryAttribute>> browseFailures() => [
    for (final (event, attributes) in logs)
      if (event == 'sync.browse_failed') attributes,
  ];

  void expectNoServerInTelemetry() {
    for (final attributes in browseFailures()) {
      for (final attribute in attributes.values) {
        expect('${attribute.value}', isNot(contains('komga.example.com')));
        expect('${attribute.value}', isNot(contains('秘密')));
      }
    }
  }

  testWidgets('a server that cannot be reached is logged once, without its '
      'address', (tester) async {
    await browse(
      tester,
      const SocketException("Failed host lookup: 'komga.example.com'"),
    );

    expect(find.text(ja.serverErrorUnknown), findsOneWidget);
    expect(find.textContaining('komga.example.com'), findsNothing);
    expect(browseFailures(), hasLength(1));
    expect(
      '${browseFailures().single['error_message']!.value}',
      'SocketException',
    );
    expectNoServerInTelemetry();
  });

  testWidgets("a server's refusal is logged with its status, not its text", (
    tester,
  ) async {
    await browse(
      tester,
      const SyncException(
        500,
        'https://komga.example.com/api/v1/books 秘密の本.cbz',
      ),
    );

    expect(find.text(ja.serverErrorStatus(status: 500)), findsOneWidget);
    expect(browseFailures(), hasLength(1));
    expect(
      '${browseFailures().single['error_message']!.value}',
      'SyncException(500)',
    );
    expectNoServerInTelemetry();
  });
}
