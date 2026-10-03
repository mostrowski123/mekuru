import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../models/remote_models.dart';
import 'server_download_route.dart';
import 'server_download_work.dart';

/// Exception for any failed server interaction. [statusCode] is 0 for
/// network-level failures (timeout, refused connection).
class SyncException implements Exception {
  final int statusCode;
  final String message;

  const SyncException(this.statusCode, this.message);

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  /// The request never reached the server (no route, refused, timed out).
  bool get isUnreachable => statusCode == 0;

  @override
  String toString() => 'SyncException($statusCode): $message';
}

/// background_downloader group of every server book download.
const serverDownloadGroup = 'server_books';

/// Application-support folder a download waits in until it is imported.
const serverDownloadsDir = 'server_downloads';

/// Cancel every server download: a full restore replaces the library they
/// would import into.
Future<void> cancelServerDownloads() async {
  InAppServerDownloads.cancelAll();
  // Host-side tests have no background downloader.
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await FileDownloader().cancelAll(group: serverDownloadGroup);
  if (Platform.isAndroid) {
    await Workmanager().cancelByTag(serverDownloadWorkTag);
    final support = await getApplicationSupportDirectory();
    await deleteServerDownloadWorkDirs(
      p.join(support.path, serverDownloadsDir),
    );
  }
}

/// The full surface Mekuru needs from a Komga/Kavita server: connection
/// test, browse, whole-file download, cover bytes, and progress get/set.
abstract class ServerClient {
  /// Throws [SyncException] when the server is unreachable or rejects the
  /// credentials; returns normally on success.
  Future<void> testConnection();

  Future<List<RemoteLibrary>> listLibraries();

  /// Series in [libraryId]; [search] filters server-side when given.
  Future<List<RemoteSeries>> listSeries(String libraryId, {String? search});

  Future<List<RemoteBook>> listBooks(RemoteSeries series);

  /// URL and headers that fetch the book's original file. The transfer
  /// itself runs in the platform's background downloader.
  Future<({String url, Map<String, String> headers})> downloadRequest(
    RemoteBook book,
  );

  /// Raw cover image bytes for a series, or null when unavailable.
  Future<List<int>?> fetchSeriesCover(RemoteSeries series);

  /// Current server-side progress for the book identified by [ids]
  /// (a [RemoteBook.ids] bundle), or null when the server has none.
  Future<RemoteProgress?> pullProgress(Map<String, String> ids);

  /// Write progress to the server for the book identified by [ids].
  Future<void> pushProgress(Map<String, String> ids, RemoteProgress progress);

  void dispose();
}
