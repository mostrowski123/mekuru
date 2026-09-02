import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';

/// [ServerClient] whose methods are unimplemented, or no-ops where a test
/// could plausibly reach them; fakes extend it and override what they
/// exercise.
class StubServerClient implements ServerClient {
  @override
  Future<void> testConnection() async {}

  @override
  Future<List<RemoteLibrary>> listLibraries() => throw UnimplementedError();

  @override
  Future<List<RemoteSeries>> listSeries(String libraryId, {String? search}) =>
      throw UnimplementedError();

  @override
  Future<List<RemoteBook>> listBooks(RemoteSeries series) =>
      throw UnimplementedError();

  @override
  Future<void> downloadBook(
    RemoteBook book,
    String destPath, {
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<List<int>?> fetchSeriesCover(RemoteSeries series) async => null;

  @override
  Future<RemoteProgress?> pullProgress(Map<String, String> ids) async => null;

  @override
  Future<void> pushProgress(
    Map<String, String> ids,
    RemoteProgress progress,
  ) async {}

  @override
  void dispose() {}
}
