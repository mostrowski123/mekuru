import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/features/sync/data/services/server_secret_storage.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart';

import 'shared/test_database.dart';
import 'test_app.dart';

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
  test('server errors are worded in the app language', () {
    final es = lookupAppLocalizations(const Locale('es'));
    String reason(Object error) => serverErrorReason(es, error);

    expect(
      reason(const SyncException(401, 'Kavita rejected the API key')),
      es.serverErrorSignInRejected,
    );
    expect(
      reason(const SyncException(403, 'Komga request failed: GET /api/v1')),
      es.serverErrorSignInRejected,
    );
    expect(
      reason(const SyncException(0, 'Cannot reach Komga server: refused')),
      es.serverErrorUnreachable,
    );
    expect(
      reason(const SyncException(500, 'Kavita request failed: GET /api')),
      'El servidor devolvió el error 500.',
    );
    // A login page or another kind of server answering 200.
    expect(reason(const FormatException('bad JSON')), es.serverErrorUnreadable);
    // What a cast of JSON in another shape throws.
    expect(reason(TypeError()), es.serverErrorUnreadable);
    // Anything else says only that it didn't work, never its text.
    expect(reason(StateError('Bad state: secret')), es.serverErrorUnknown);
  });

  test('a secure connection that cannot be made says to check http and '
      'https', () {
    final ja = lookupAppLocalizations(const Locale('ja'));
    // https typed for a server that only speaks http.
    const wrongProtocol = HandshakeException(
      'Handshake error in client (OS Error: '
      'WRONG_VERSION_NUMBER(tls_record.cc:127))',
    );
    expect(
      serverErrorReason(ja, wrongProtocol),
      'サーバーと安全に接続できませんでした。サーバーが https を使っていない場合は、'
      'アドレスを http:// で始めてください。',
    );
    expect(
      serverErrorReason(ja, const TlsException('no shared cipher')),
      ja.serverErrorSecureConnection,
    );
    // A certificate the device does not trust keeps its own words, also for
    // a caller that did not check for it first.
    const untrusted = HandshakeException(
      'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
      'self signed certificate(handshake.cc:393))',
    );
    expect(serverErrorReason(ja, untrusted), ja.serverCertificateUntrusted);
  });

  test('a failed server download is worded once, in the app language', () {
    final es = lookupAppLocalizations(const Locale('es'));
    String describe(Object error) =>
        describeServerDownloadError(es, serverDownloadErrorCode(error));

    expect(
      describe(const ServerDownloadHttpException(401)),
      'Error al descargar: ${es.serverErrorSignInRejected}',
    );
    expect(
      describe(const ServerDownloadHttpException(500)),
      'Error al descargar: El servidor devolvió el error 500.',
    );
    expect(
      describe(const SocketException('Connection refused')),
      'Error al descargar: ${es.serverErrorUnreachable}',
    );
    // iOS rebuilding the request of a download the app was closed in.
    expect(
      describe(const SyncException(401, 'Kavita rejected the API key')),
      'Error al descargar: ${es.serverErrorSignInRejected}',
    );
    expect(
      describeServerDownloadError(es, serverDownloadInterruptedError),
      es.serverBrowseDownloadInterrupted,
    );
    expect(
      describeServerDownloadError(es, serverDownloadConnectionGoneError),
      'Error al descargar: ${es.serverErrorConnectionGone}',
    );
    // The disk filled mid-download.
    expect(
      describeServerDownloadError(es, serverDownloadStorageFullError),
      'Error al descargar: ${es.localOcrStorageFull}',
    );
    // Anything else says only that it didn't finish, never its text.
    expect(describe(const FormatException('bad zip')), es.downloadNotFinished);
  });

  testWidgets('link existing books survives an async secret load', (
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
        child: buildLocalizedTestApp(home: const ServerSettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.playlist_add_check));
    // flutter_test answers every HTTP request with 400, so a healthy run
    // fails at the network layer. The regression failed earlier, while the
    // client was still being built: the flow once read the autoDispose
    // client provider without a listener, so it was disposed mid-build.
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

  testWidgets('in Japanese, linking that fails says why without the '
      "error's text", (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final db = createTestDatabase();
    addTearDown(db.close);
    await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'komga',
            name: 'Home',
            baseUrl: 'http://127.0.0.1:9',
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // A login page answering in place of the server.
          serverClientFactoryProvider.overrideWithValue(
            (_) async => throw const FormatException('<html>Sign in'),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const ServerSettingsScreen(),
          locale: const Locale('ja'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.playlist_add_check));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.text(ja.serverSettingsLinkFailed(error: ja.serverErrorUnreadable)),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp('Exception|<html>')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the edit dialog saves the self-signed certificate switch', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final id = await db
        .into(db.serverConnections)
        .insert(
          ServerConnectionsCompanion.insert(
            serverType: 'komga',
            name: 'Home',
            baseUrl: 'https://192.168.1.5:25600',
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          serverSecretStorageProvider.overrideWithValue(_SlowFakeSecrets()),
        ],
        child: buildLocalizedTestApp(home: const ServerSettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final toggle = find.byKey(
      const ValueKey('server_dialog_allow_self_signed'),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Accept self-signed certificate'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final row = await tester.runAsync(
      () => (db.select(
        db.serverConnections,
      )..where((t) => t.id.equals(id))).getSingle(),
    );
    expect(row!.allowSelfSignedCert, isTrue);

    // Unmount so drift's stream-close timer fires before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the self-signed switch shows only for an https URL', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: buildLocalizedTestApp(home: const ServerSettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final toggle = find.byKey(
      const ValueKey('server_dialog_allow_self_signed'),
    );
    final url = find.widgetWithText(TextField, 'Server URL');
    expect(toggle, findsNothing);

    await tester.enterText(url, 'http://nas.lan:25600');
    await tester.pump();
    expect(toggle, findsNothing);

    await tester.enterText(url, 'https://nas.lan:25600');
    await tester.pump();
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
