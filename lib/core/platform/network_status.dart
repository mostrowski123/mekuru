import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

const _iosChannel = MethodChannel('mekuru/network');

/// Whether a large download can start without asking about mobile data. On
/// Android the active network is Wi-Fi; on iOS it is neither cellular or a
/// hotspot nor in Low Data Mode. False when the check fails, so callers ask
/// rather than spend the user's data.
Future<bool> isOnWifi() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _iosChannel.invokeMethod<bool>('isUnmetered') ?? false;
    }
    return await LocalMangaOcr.isWifiConnected();
  } catch (e, st) {
    logFailure('network.wifi_check_failed', e, stackTrace: st);
    return false;
  }
}

/// A transfer stopped by [whileOnWifi] because the network stopped being
/// Wi-Fi.
class WifiLostException implements Exception {
  const WifiLostException();
}

/// Runs [transfer], which downloads through [client], only on Wi-Fi
/// ([isOnWifi]): it doesn't start off Wi-Fi, and [client] is force-closed
/// when the network stops being Wi-Fi, so the transfer fails with
/// [WifiLostException] instead of going on over mobile data. A transfer that
/// fails for another reason while off Wi-Fi (the Wi-Fi socket died) reports
/// the same. The caller still closes [client].
// ponytail: a connection opened on Wi-Fi stays on it, so the poll only matters
// when the network changes under it (Low Data Mode switched on), and stops it
// up to [every] late. A URLSession with allowsConstrainedNetworkAccess = false
// would be exact.
Future<T> whileOnWifi<T>(
  HttpClient client,
  Future<T> Function() transfer, {
  Duration every = const Duration(seconds: 2),
}) async {
  if (!await isOnWifi()) throw const WifiLostException();
  var lost = false;
  final watch = Timer.periodic(every, (_) async {
    if (lost || await isOnWifi()) return;
    lost = true;
    client.close(force: true);
  });
  try {
    return await transfer();
  } catch (_) {
    if (lost || !await isOnWifi()) throw const WifiLostException();
    rethrow;
  } finally {
    watch.cancel();
  }
}
