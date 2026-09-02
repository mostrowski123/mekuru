/// Server-agnostic models for Komga/Kavita browsing and progress sync.
///
/// Per-server identity lives in an opaque string-to-string id bundle
/// ([RemoteBook.ids]) — Komga: `{bookId, seriesId}`; Kavita: `{chapterId,
/// volumeId, seriesId, libraryId}` — which is also what gets persisted as
/// raw JSON in `Books.remoteIds`.
library;

/// Supported self-hosted server types.
enum ServerType {
  komga('komga'),
  kavita('kavita');

  final String storageValue;
  const ServerType(this.storageValue);

  static ServerType fromStorage(String value) => ServerType.values.firstWhere(
    (t) => t.storageValue == value,
    orElse: () => throw ArgumentError('Unknown server type: $value'),
  );

  String get displayName => switch (this) {
    ServerType.komga => 'Komga',
    ServerType.kavita => 'Kavita',
  };

  /// [displayName] for a stored value; the raw value for a type this build
  /// doesn't know (a connection restored from a newer version's backup).
  static String displayNameOf(String value) =>
      ServerType.values
          .where((t) => t.storageValue == value)
          .firstOrNull
          ?.displayName ??
      value;
}

class RemoteLibrary {
  final String id;
  final String name;

  const RemoteLibrary({required this.id, required this.name});
}

class RemoteSeries {
  final String id;
  final String libraryId;
  final String title;
  final int bookCount;

  const RemoteSeries({
    required this.id,
    required this.libraryId,
    required this.title,
    required this.bookCount,
  });
}

/// Book format as far as Mekuru cares: what importer handles the download.
enum RemoteBookFormat { epub, imageArchive }

class RemoteBook {
  /// Opaque per-server id bundle; persisted verbatim in `Books.remoteIds`.
  final Map<String, String> ids;
  final String title;
  final String seriesTitle;
  final RemoteBookFormat format;
  final int pageCount;

  const RemoteBook({
    required this.ids,
    required this.title,
    required this.seriesTitle,
    required this.format,
    required this.pageCount,
  });

  /// Extension the downloaded file should get so the right importer runs.
  String get fileExtension =>
      format == RemoteBookFormat.epub ? '.epub' : '.cbz';
}

/// Reading progress as reported by (or pushed to) a server.
class RemoteProgress {
  /// Current page as a 0-based index; null when the server has no page info.
  /// Clients normalize their server's native numbering to this.
  final int? page;
  final bool completed;

  /// EPUB locator: spine item href and progression within it (0..1).
  final String? href;
  final double? progression;

  /// Progression through the whole book (0..1).
  final double? totalProgression;

  /// Server-side timestamp of the progress record, for conflict resolution.
  final DateTime? lastModified;

  const RemoteProgress({
    this.page,
    this.completed = false,
    this.href,
    this.progression,
    this.totalProgression,
    this.lastModified,
  });
}
