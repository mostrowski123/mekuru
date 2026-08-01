import 'package:mekuru/core/database/database_provider.dart';

/// Row builders shared by the stats tests.
///
/// `bookId` and `wordsSaved` are fixed rather than exposed as knobs: nothing
/// downstream of these rows reads either, so a parameter for them would imply
/// the aggregator cares about book identity or saved-word counts.
ReadingSession session({
  int id = 0,
  String bookFormat = 'epub',
  required DateTime startedAt,
  int durationMs = 0,
  int pagesTurned = 0,
  int charactersRead = 0,
  int lookups = 0,
}) => ReadingSession(
  id: id,
  bookId: null,
  bookFormat: bookFormat,
  startedAt: startedAt,
  durationMs: durationMs,
  pagesTurned: pagesTurned,
  charactersRead: charactersRead,
  lookups: lookups,
  wordsSaved: 0,
);

WordEvent wordEvent({
  int id = 0,
  String kind = 'saved',
  required String expression,
  String source = 'epub',
  required DateTime createdAt,
}) => WordEvent(
  id: id,
  kind: kind,
  expression: expression,
  source: source,
  createdAt: createdAt,
);
