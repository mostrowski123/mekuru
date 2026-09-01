import '../models/remote_models.dart';

/// Exception for any failed server interaction. [statusCode] is 0 for
/// network-level failures (timeout, refused connection).
class SyncException implements Exception {
  final int statusCode;
  final String message;

  const SyncException(this.statusCode, this.message);

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'SyncException($statusCode): $message';
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

  /// Download the book's original file to [destPath].
  Future<void> downloadBook(
    RemoteBook book,
    String destPath, {
    void Function(double progress)? onProgress,
  });

  /// Raw cover image bytes for a series, or null when unavailable.
  Future<List<int>?> fetchSeriesCover(RemoteSeries series);

  /// Current server-side progress for the book identified by [ids]
  /// (a [RemoteBook.ids] bundle), or null when the server has none.
  Future<RemoteProgress?> pullProgress(Map<String, String> ids);

  /// Write progress to the server for the book identified by [ids].
  Future<void> pushProgress(Map<String, String> ids, RemoteProgress progress);

  void dispose();
}
