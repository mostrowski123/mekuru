import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/sync/data/services/server_download_route.dart';

void main() {
  group('serverDownloadRoute', () {
    ServerDownloadRoute route(
      String url, {
      bool allowSelfSigned = false,
      bool isIos = true,
    }) => serverDownloadRoute(
      url: url,
      allowSelfSigned: allowSelfSigned,
      isIos: isIos,
    );

    test('an accepted self-signed certificate downloads in the app', () {
      for (final isIos in [true, false]) {
        expect(
          route('https://192.168.1.5/f', allowSelfSigned: true, isIos: isIos),
          ServerDownloadRoute.inApp,
        );
      }
    });

    test('iOS downloads plain http to a domain name in the app', () {
      expect(route('http://nas.tail1234.ts.net/f'), ServerDownloadRoute.inApp);
      expect(
        route('http://komga.example.com:25600/f'),
        ServerDownloadRoute.inApp,
      );
    });

    test('iOS keeps the local network and https in the background', () {
      for (final url in [
        'http://192.168.10.115:25600/f',
        'http://127.0.0.1:25600/f',
        'http://[fd00::1]:8080/f',
        'http://localhost:25600/f',
        'http://nas.local:25600/f',
        'http://nas:25600/f',
        'https://komga.example.com/f',
      ]) {
        expect(route(url), ServerDownloadRoute.background, reason: url);
      }
    });

    test('Android keeps plain http to a domain name in the background', () {
      expect(
        route('http://komga.example.com/f', isIos: false),
        ServerDownloadRoute.background,
      );
    });
  });

  test('isLocalNetworkHost', () {
    expect(isLocalNetworkHost('10.0.0.2'), isTrue);
    expect(isLocalNetworkHost('fd00::1'), isTrue);
    expect(isLocalNetworkHost('LOCALHOST'), isTrue);
    expect(isLocalNetworkHost('nas.local'), isTrue);
    expect(isLocalNetworkHost('nas'), isTrue);
    expect(isLocalNetworkHost('nas.lan'), isFalse);
    expect(isLocalNetworkHost('example.com'), isFalse);
  });

  test('InAppServerDownloads.cancelAll stops and marks running downloads', () {
    final client = HttpClient();
    InAppServerDownloads.start('b1', client);
    expect(InAppServerDownloads.isIdle, isFalse);

    InAppServerDownloads.cancelAll();

    expect(InAppServerDownloads.isIdle, isTrue);
    expect(InAppServerDownloads.wasCancelled('b1'), isTrue);
    // A closed client refuses new requests.
    expect(
      () => client.getUrl(Uri.parse('http://127.0.0.1/')),
      throwsStateError,
    );

    // Starting the same key again clears the cancelled mark.
    InAppServerDownloads.start('b1', HttpClient());
    expect(InAppServerDownloads.wasCancelled('b1'), isFalse);
    InAppServerDownloads.finish('b1');
    expect(InAppServerDownloads.isIdle, isTrue);
  });
}
