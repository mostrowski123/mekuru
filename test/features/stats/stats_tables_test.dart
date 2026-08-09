import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';

import '../../shared/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  test('reading session insert round-trips', () async {
    await db
        .into(db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: const Value(1),
            bookFormat: 'epub',
            startedAt: DateTime(2026, 8, 1, 21, 30),
            durationMs: 90000,
            pagesTurned: const Value(12),
            charactersRead: const Value(3400),
            lookups: const Value(5),
            wordsSaved: const Value(2),
          ),
        );
    final rows = await db.select(db.readingSessions).get();
    expect(rows.single.charactersRead, 3400);
    expect(rows.single.bookFormat, 'epub');
  });

  test('backfill SQL copies saved words into word_events', () async {
    await db
        .into(db.savedWords)
        .insert(
          SavedWordsCompanion.insert(expression: '猫', glossaries: '["cat"]'),
        );
    await db.customStatement(
      "INSERT INTO word_events (kind, expression, source, created_at) "
      "SELECT 'saved', expression, 'other', date_added FROM saved_words",
    );
    final events = await db.select(db.wordEvents).get();
    expect(events.single.kind, 'saved');
    expect(events.single.expression, '猫');
    expect(events.single.source, 'other');
  });
}
