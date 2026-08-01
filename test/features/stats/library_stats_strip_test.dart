import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/stats/presentation/widgets/library_stats_strip.dart';

import '../../test_app.dart';

ReadingSession _session({
  required int id,
  required DateTime startedAt,
  int durationMs = 0,
  int charactersRead = 0,
}) {
  return ReadingSession(
    id: id,
    bookFormat: 'epub',
    startedAt: startedAt,
    durationMs: durationMs,
    pagesTurned: 0,
    charactersRead: charactersRead,
    lookups: 0,
    wordsSaved: 0,
  );
}

void main() {
  group('LibraryStatsStrip', () {
    Future<void> pumpStrip(
      WidgetTester tester,
      Stream<List<ReadingSession>> sessions,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith((ref) => sessions),
            // Only the pushed stats screen reads this one; the strip itself
            // never touches vocabulary.
            wordEventsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: buildLocalizedTestApp(
            home: const Scaffold(
              // Top-aligned so an invisible strip really measures zero rather
              // than being stretched by the body's constraints.
              body: Align(
                alignment: Alignment.topCenter,
                child: LibraryStatsStrip(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders nothing before anything has been read', (
      tester,
    ) async {
      await pumpStrip(tester, Stream.value(const []));

      expect(find.byType(Card), findsNothing);
      expect(tester.getSize(find.byType(LibraryStatsStrip)), Size.zero);
    });

    testWidgets('shows the trailing week totals', (tester) async {
      await pumpStrip(
        tester,
        Stream.value([
          _session(
            id: 1,
            startedAt: DateTime.now(),
            durationMs: (3 * 60 + 20) * 60 * 1000,
            charactersRead: 1200,
          ),
        ]),
      );

      expect(find.text('This week'), findsOneWidget);
      expect(find.textContaining('3h 20m'), findsOneWidget);
      expect(find.textContaining('1,200'), findsOneWidget);
    });

    testWidgets('ignores the sessions outside the trailing week', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpStrip(
        tester,
        Stream.value([
          _session(
            id: 1,
            startedAt: DateTime(now.year, now.month, now.day - 30),
            durationMs: 60 * 60 * 1000,
            charactersRead: 5000,
          ),
        ]),
      );

      // History exists, so the strip stays — reporting a quiet week is
      // factual, and hiding it would make the entry point come and go.
      expect(find.byType(Card), findsOneWidget);
      expect(find.textContaining('0m'), findsOneWidget);
      expect(find.textContaining('5,000'), findsNothing);
    });

    testWidgets('opens the stats screen when tapped', (tester) async {
      await pumpStrip(
        tester,
        Stream.value([
          _session(
            id: 1,
            startedAt: DateTime.now(),
            durationMs: 60 * 60 * 1000,
            charactersRead: 400,
          ),
        ]),
      );

      expect(find.byType(StatsScreen), findsNothing);

      await tester.tap(find.byType(LibraryStatsStrip));
      await tester.pumpAndSettle();

      expect(find.byType(StatsScreen), findsOneWidget);
    });

    testWidgets('renders nothing when the stats cannot be read', (
      tester,
    ) async {
      await pumpStrip(tester, Stream.error(Exception('database is gone')));

      expect(find.byType(Card), findsNothing);
      expect(tester.getSize(find.byType(LibraryStatsStrip)), Size.zero);
    });

    testWidgets('renders nothing while the stats are still loading', (
      tester,
    ) async {
      final pending = Completer<List<ReadingSession>>();
      addTearDown(() => pending.complete(const []));
      await pumpStrip(tester, Stream.fromFuture(pending.future));

      expect(find.byType(Card), findsNothing);
      expect(tester.getSize(find.byType(LibraryStatsStrip)), Size.zero);
    });
  });
}
