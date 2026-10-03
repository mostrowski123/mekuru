import 'dart:io';

/// How a server book download runs.
enum ServerDownloadRoute {
  /// background_downloader: WorkManager on Android, a background URLSession
  /// on iOS. Survives leaving and closing the app.
  background,

  /// dart:io inside the app: works only while Mekuru is open.
  inApp,
}

/// Which downloader can fetch [url]. The platform downloaders can't accept a
/// self-signed certificate for one server only (background_downloader has no
/// such option on iOS, and on Android only a process-wide one it refuses in
/// release builds), so a server whose certificate the user accepted
/// downloads in the app. On iOS, App Transport Security also blocks plain
/// http to a domain name outside the local network; dart:io is not subject
/// to it.
ServerDownloadRoute serverDownloadRoute({
  required String url,
  required bool allowSelfSigned,
  required bool isIos,
}) {
  if (allowSelfSigned) return ServerDownloadRoute.inApp;
  final uri = Uri.tryParse(url);
  if (isIos &&
      uri != null &&
      uri.scheme == 'http' &&
      !isLocalNetworkHost(uri.host)) {
    return ServerDownloadRoute.inApp;
  }
  return ServerDownloadRoute.background;
}

/// Hosts the app's `NSAllowsLocalNetworking` exception covers: IP addresses,
/// `localhost`, `.local` names and single-label names.
bool isLocalNetworkHost(String host) {
  final lower = host.toLowerCase();
  if (InternetAddress.tryParse(lower) != null) return true;
  return lower == 'localhost' ||
      lower.endsWith('.local') ||
      !lower.contains('.');
}

/// In-app downloads that are running, by download key, so a full restore can
/// stop them together with the background ones (`cancelServerDownloads`).
class InAppServerDownloads {
  InAppServerDownloads._();

  static final _clients = <String, HttpClient>{};
  static final _cancelled = <String>{};

  static void start(String key, HttpClient client) {
    _cancelled.remove(key);
    _clients[key] = client;
  }

  static void finish(String key) => _clients.remove(key);

  static bool get isIdle => _clients.isEmpty;

  /// Whether [key] ended because [cancelAll] stopped it.
  static bool wasCancelled(String key) => _cancelled.contains(key);

  /// Abort every running in-app download.
  static void cancelAll() {
    for (final entry in _clients.entries) {
      _cancelled.add(entry.key);
      entry.value.close(force: true);
    }
    _clients.clear();
  }
}
