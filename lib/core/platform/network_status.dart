import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

const _iosChannel = MethodChannel('mekuru/network');

/// Whether a large download can start without asking about mobile data. On
/// Android the active network is Wi-Fi that isn't metered (not a hotspot);
/// on iOS it is neither cellular or a hotspot nor in Low Data Mode. False
/// when the check fails, so callers ask rather than spend the user's data.
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

/// Whether there is any network to download over: an active network on
/// Android, a path that is not unsatisfied on iOS; false in airplane mode.
/// True where it can't tell, so the caller asks or tries as before: when the
/// check fails or has no answer.
Future<bool> isConnected() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _iosChannel.invokeMethod<bool>('isConnected') ?? true;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await LocalMangaOcr.isNetworkConnected();
  } catch (e, st) {
    logFailure('network.connection_check_failed', e, stackTrace: st);
    return true;
  }
}

/// Whether a VPN carries the traffic (Android): Android counts most VPNs as
/// metered, so [isOnWifi] is false on Wi-Fi under one, and the mobile-data
/// question says the VPN is why. False off Android or when the check fails.
Future<bool> isOnVpn() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await LocalMangaOcr.isVpnActive();
  } catch (e, st) {
    logFailure('network.vpn_check_failed', e, stackTrace: st);
    return false;
  }
}

/// The network one add-on download may use: the answer to the mobile-data
/// question (`askNetwork`, lib/shared/widgets/mobile_data_dialog.dart).
/// Every add-on download takes one, so none starts without the question.
enum NetworkConsent {
  /// On Wi-Fi, so nothing was asked: the download stops when Wi-Fi goes
  /// ([whileOnWifi]), or, as an Android download job, waits for it.
  wifiOnly,

  /// The user tapped Download in the question: this one download, its
  /// retries and its job across relaunches included, may use mobile data.
  mobileData;

  bool get allowsMobileData => this == mobileData;
}

/// A transfer stopped by [whileOnWifi] because the network stopped being
/// Wi-Fi.
class WifiLostException implements UserSideFailure {
  const WifiLostException();
}

/// A transfer that failed while Android had Mekuru in the background, where
/// it blocks the app's network after a while.
class DownloadStoppedInBackgroundException implements UserSideFailure {
  const DownloadStoppedInBackgroundException([this.cause]);

  /// What the transfer threw, for the log; null when it never started.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DownloadStoppedInBackgroundException'
      : 'DownloadStoppedInBackgroundException: $cause';
}

/// Runs [transfer], which downloads through [client], only on Wi-Fi
/// ([isOnWifi]): it doesn't start off Wi-Fi, and [client] is force-closed
/// when the network stops being Wi-Fi, so the transfer fails with
/// [WifiLostException] instead of going on over mobile data. A transfer that
/// fails for another reason while off Wi-Fi (the Wi-Fi socket died) reports
/// the same. On Android in the background the Wi-Fi check reads false
/// because the app's network is blocked, so it isn't watched there, and a
/// transfer that can't start or fails then reports
/// [DownloadStoppedInBackgroundException].
/// The caller still closes [client].
// ponytail: a connection opened on Wi-Fi stays on it, so the poll only matters
// when the network changes under it (Low Data Mode switched on), and stops it
// up to [every] late. A URLSession with allowsConstrainedNetworkAccess = false
// would be exact.
Future<T> whileOnWifi<T>(
  HttpClient client,
  Future<T> Function() transfer, {
  Duration every = const Duration(seconds: 2),
}) async {
  if (!await isOnWifi()) {
    throw _inAndroidBackground()
        ? const DownloadStoppedInBackgroundException()
        : const WifiLostException();
  }
  var lost = false;
  final watch = Timer.periodic(every, (_) async {
    if (lost || _inAndroidBackground()) return;
    if (await isOnWifi() || _inAndroidBackground()) return;
    lost = true;
    client.close(force: true);
  });
  try {
    return await transfer();
  } catch (e) {
    if (lost) throw const WifiLostException();
    if (_inAndroidBackground()) throw DownloadStoppedInBackgroundException(e);
    if (!await isOnWifi()) throw const WifiLostException();
    rethrow;
  } finally {
    watch.cancel();
  }
}

/// Mekuru is on Android and out of sight, where Android blocks its network
/// about 30 s later. A pulled-down shade (inactive) is still the foreground.
bool _inAndroidBackground() =>
    defaultTargetPlatform == TargetPlatform.android &&
    switch (SchedulerBinding.instance.lifecycleState) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
      _ => false,
    };
