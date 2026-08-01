import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/stats/presentation/widgets/hero_stat_tile.dart';

import '../../test_app.dart';

ReadingSession _session({
  required int id,
  required DateTime startedAt,
  String bookFormat = 'epub',
  int durationMs = 0,
  int charactersRead = 0,
}) {
  return ReadingSession(
    id: id,
    bookFormat: bookFormat,
    startedAt: startedAt,
    durationMs: durationMs,
    pagesTurned: 0,
    charactersRead: charactersRead,
    lookups: 0,
    wordsSaved: 0,
  );
}

WordEvent _event({
  required int id,
  required String expression,
  required DateTime createdAt,
  String source = 'epub',
}) {
  return WordEvent(
    id: id,
    kind: 'saved',
    expression: expression,
    source: source,
    createdAt: createdAt,
  );
}

void main() {
  group('formatDuration', () {
    test('renders nothing-read as zero minutes', () {
      expect(formatDuration(0), '0m');
    });

    test('drops the hour part below an hour', () {
      expect(formatDuration(42 * 60 * 1000), '42m');
    });

    test('renders hours and minutes together', () {
      expect(formatDuration((3 * 60 + 20) * 60 * 1000), '3h 20m');
    });

    test('keeps counting in hours past a day', () {
      expect(formatDuration((30 * 60 + 5) * 60 * 1000), '30h 5m');
    });

    test('floors sub-minute leftovers instead of rounding up', () {
      expect(formatDuration(59 * 1000), '0m');
      expect(formatDuration(119 * 1000), '1m');
    });

    test('clamps a negative duration rather than showing a minus sign', () {
      expect(formatDuration(-5000), '0m');
    });
  });

  group('StatsScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required List<ReadingSession> sessions,
      required List<WordEvent> events,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith((ref) => Stream.value(sessions)),
            wordEventsProvider.overrideWith((ref) => Stream.value(events)),
          ],
          child: buildLocalizedTestApp(home: const StatsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the hero tiles and both selectors', (tester) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        sessions: [
          _session(
            id: 1,
            startedAt: now,
            durationMs: (3 * 60 + 20) * 60 * 1000,
            charactersRead: 1200,
          ),
        ],
        events: [_event(id: 1, expression: '本', createdAt: now)],
      );

      expect(find.byType(HeroStatTile), findsNWidgets(3));
      expect(find.text('3h 20m'), findsOneWidget);
      expect(find.text('Reading time'), findsOneWidget);
      expect(find.text('Characters read'), findsOneWidget);
      expect(find.text('Words added'), findsOneWidget);

      expect(find.byType(SegmentedButton<StatsFormat>), findsOneWidget);
      expect(find.byType(SegmentedButton<StatsPeriod>), findsOneWidget);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
    });

    testWidgets('renders zeroed tiles with no data at all', (tester) async {
      await pumpScreen(tester, sessions: const [], events: const []);

      expect(find.byType(HeroStatTile), findsNWidgets(3));
      expect(find.text('0m'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('shows a quiet message when the stats cannot be read', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(
              (ref) => Stream.error(Exception('database is gone')),
            ),
            wordEventsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: buildLocalizedTestApp(home: const StatsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Reading stats aren't available right now."),
        findsOneWidget,
      );
      expect(find.byType(HeroStatTile), findsNothing);
      // The selectors stay usable — only the numbers are missing.
      expect(find.byType(SegmentedButton<StatsPeriod>), findsOneWidget);
    });

    testWidgets('re-reads totals when the format filter changes', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        sessions: [
          _session(
            id: 1,
            startedAt: now,
            bookFormat: 'epub',
            durationMs: 60 * 60 * 1000,
          ),
          _session(
            id: 2,
            startedAt: now,
            bookFormat: 'manga',
            durationMs: 30 * 60 * 1000,
          ),
        ],
        events: const [],
      );
      expect(find.text('1h 30m'), findsOneWidget);

      await tester.tap(find.text('Manga'));
      await tester.pumpAndSettle();

      expect(find.text('30m'), findsOneWidget);
    });

    testWidgets('counts a word once, in the period it was first seen', (
      tester,
    ) async {
      final now = DateTime.now();
      final lastYear = DateTime(now.year - 1, now.month, now.day);
      await pumpScreen(
        tester,
        sessions: const [],
        events: [
          _event(id: 1, expression: '本', createdAt: lastYear),
          // Same expression again this week: already counted, not a new word.
          _event(id: 2, expression: '本', createdAt: now),
          _event(id: 3, expression: '猫', createdAt: now),
        ],
      );

      // Week: only 猫 is new.
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();

      // All: both distinct expressions, including the one predating any
      // session.
      expect(find.text('2'), findsOneWidget);
    });
  });
}
