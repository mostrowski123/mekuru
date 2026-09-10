import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/features/wanikani/presentation/screens/wanikani_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/wanikani_test_fakes.dart';
import '../../test_app.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  late FakeWanikaniApiClient client;
  late FakeWanikaniStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = FakeWanikaniApiClient();
    storage = FakeWanikaniStorage();
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        wanikaniApiClientProvider.overrideWithValue(client),
        wanikaniStorageProvider.overrideWithValue(storage),
        wanikaniClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(wanikaniProvider.notifier).loadPersistedSettings();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(home: const WanikaniSettingsScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('unlinked: token field, token-page button, disabled link', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('wanikani-token-field')), findsOneWidget);
    expect(find.text('Get an API token'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    final link = tester.widget<FilledButton>(
      find.byKey(const Key('wanikani-link')),
    );
    expect(link.onPressed, isNull);
    expect(find.byKey(const Key('wanikani-sync-now')), findsNothing);
  });

  testWidgets('linking with a valid token shows the linked account', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('wanikani-token-field')),
      'tok-1',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('wanikani-link')));
    await tester.pumpAndSettle();

    expect(find.text('Linked as crabigator'), findsOneWidget);
    expect(find.textContaining('Level 5 · 2 kanji synced'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(find.byKey(const Key('wanikani-sync-now')), findsOneWidget);
    expect(find.byKey(const Key('wanikani-unlink')), findsOneWidget);
    expect(find.byKey(const Key('wanikani-token-field')), findsNothing);
    expect(storage.token, 'tok-1');
  });

  testWidgets('a rejected token shows the inline error and stays unlinked', (
    tester,
  ) async {
    client.error = const WanikaniException(
      WanikaniException.tokenInvalid,
      statusCode: 401,
    );
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('wanikani-token-field')), 'x');
    await tester.pump();
    await tester.tap(find.byKey(const Key('wanikani-link')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'WaniKani rejected this token. Create a new one and try again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('wanikani-token-field')), findsOneWidget);
    expect(storage.token, isNull);
  });

  testWidgets('network and rate-limit failures get their own wording', (
    tester,
  ) async {
    client.error = const WanikaniException(WanikaniException.network);
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const Key('wanikani-token-field')), 'x');
    await tester.pump();
    await tester.tap(find.byKey(const Key('wanikani-link')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach WaniKani"), findsOneWidget);

    client.error = const WanikaniException(
      WanikaniException.rateLimited,
      statusCode: 429,
    );
    await tester.tap(find.byKey(const Key('wanikani-link')));
    await tester.pumpAndSettle();
    expect(find.textContaining('rate limiting'), findsOneWidget);

    client.error = const WanikaniException(
      WanikaniException.http,
      statusCode: 500,
    );
    await tester.tap(find.byKey(const Key('wanikani-link')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Try again later'), findsOneWidget);
  });

  testWidgets('sync now reports success and failure in a snackbar', (
    tester,
  ) async {
    storage
      ..token = 'tok'
      ..snapshot = snapshotAt(now);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('wanikani-sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Synced 2 kanji'), findsOneWidget);
    // Let the success snackbar time out; the messenger queues them.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    client.error = const WanikaniException(WanikaniException.network);
    await tester.tap(find.byKey(const Key('wanikani-sync-now')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach WaniKani"), findsOneWidget);
    // Still linked with the previous snapshot.
    expect(find.text('Linked as crabigator'), findsOneWidget);

    // Let the snackbar timers expire so the test ends with none pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('unlink asks for confirmation, then returns to the link form', (
    tester,
  ) async {
    storage
      ..token = 'tok'
      ..snapshot = snapshotAt(now);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('wanikani-unlink')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.token, 'tok');

    await tester.tap(find.byKey(const Key('wanikani-unlink')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unlink').last);
    await tester.pumpAndSettle();

    expect(storage.token, isNull);
    expect(storage.snapshot, isNull);
    expect(find.byKey(const Key('wanikani-token-field')), findsOneWidget);
  });

  testWidgets('a restored snapshot without a token shows the reconnect note', (
    tester,
  ) async {
    storage.snapshot = snapshotAt(now);
    await pumpScreen(tester);

    expect(
      find.textContaining('Kanji list restored from a backup'),
      findsOneWidget,
    );
    expect(find.text('Level 5 · 2 kanji synced'), findsOneWidget);
    expect(find.byKey(const Key('wanikani-token-field')), findsOneWidget);
    expect(find.byKey(const Key('wanikani-sync-now')), findsNothing);
  });
}
