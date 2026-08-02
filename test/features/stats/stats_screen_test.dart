import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/stats/presentation/stats_formatting.dart';
import 'package:mekuru/features/stats/presentation/widgets/activity_heatmap_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/hero_stat_tile.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/l10n/generated/app_localizations_zh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_app.dart';
import 'stats_fixtures.dart';

void main() {
  group('formatDuration', () {
    // The per-locale classes gen_l10n emits need no widget tree, so these stay
    // plain `test`s rather than pumping a MaterialApp for a string.
    final en = AppLocalizationsEn();

    test('renders nothing-read as zero minutes', () {
      expect(formatDuration(en, 0), '0m');
    });

    test('drops the hour part below an hour', () {
      expect(formatDuration(en, 42 * 60 * 1000), '42m');
    });

    test('renders hours and minutes together', () {
      expect(formatDuration(en, (3 * 60 + 20) * 60 * 1000), '3h 20m');
    });

    test('keeps counting in hours past a day', () {
      expect(formatDuration(en, (30 * 60 + 5) * 60 * 1000), '30h 5m');
    });

    test('floors sub-minute leftovers instead of rounding up', () {
      expect(formatDuration(en, 59 * 1000), '0m');
      expect(formatDuration(en, 119 * 1000), '1m');
    });

    test('clamps a negative duration rather than showing a minus sign', () {
      expect(formatDuration(en, -5000), '0m');
    });

    test('reads its units off the locale rather than hardcoding h and m', () {
      // Asserted against the l10n object's own message, not a literal: zh
      // carries the English wording today, and the point is that whenever it
      // is translated the formatter follows without a code change.
      final zh = AppLocalizationsZh();
      expect(
        formatDuration(zh, (3 * 60 + 20) * 60 * 1000),
        zh.statsDurationHoursMinutes(hours: 3, minutes: 20),
      );
      expect(
        formatDuration(zh, 42 * 60 * 1000),
        zh.statsDurationMinutes(minutes: 42),
      );
    });
  });

  group('formatCompactCount', () {
    test('keeps small counts exact with grouping', () {
      expect(formatCompactCount('en', 0), '0');
      expect(formatCompactCount('en', 500), '500');
      expect(formatCompactCount('en', 9999), '9,999');
    });

    test('condenses five digits and up with at most one decimal', () {
      expect(formatCompactCount('en', 37862), '37.9K');
      expect(formatCompactCount('en', 12000), '12K');
      expect(formatCompactCount('en', 1234567), '1.2M');
    });

    test('count-up frames keep the final value\'s representation', () {
      // The tile animates through intermediate values; the format is chosen
      // from where the count will land, so the string never flips from
      // "9,999" to "10K" mid-flight.
      final format = compactCountFormatter('en', 37862);
      expect(format(500), '500');
      expect(format(9999), '10K');
      expect(format(37862), '37.9K');
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

    // The chart cards below the tiles label their own axes with durations and
    // counts, so a headline figure has to be looked for where it is claimed
    // to be rather than anywhere on the screen.
    Finder inHero(String text) => find.descendant(
      of: find.byType(HeroStatTile),
      matching: find.text(text),
    );

    testWidgets('titles itself You and opens settings from the gear', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScreen(tester, sessions: [], events: []);

      expect(find.text('You'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shows the hero tiles and both selectors', (tester) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        sessions: [
          session(
            id: 1,
            startedAt: now,
            durationMs: (3 * 60 + 20) * 60 * 1000,
            charactersRead: 1200,
          ),
        ],
        events: [wordEvent(id: 1, expression: '本', createdAt: now)],
      );

      expect(find.byType(HeroStatTile), findsNWidgets(3));
      expect(inHero('3h 20m'), findsOneWidget);
      expect(inHero('Reading time'), findsOneWidget);
      expect(inHero('Characters read'), findsOneWidget);
      expect(inHero('Words added'), findsOneWidget);

      expect(find.byType(SegmentedButton<StatsFormat>), findsOneWidget);
      expect(find.byType(SegmentedButton<StatsPeriod>), findsOneWidget);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
    });

    testWidgets('centers each hero figure over its label in even thirds', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        sessions: [
          session(
            id: 1,
            startedAt: now,
            durationMs: 60000,
            charactersRead: 37862,
          ),
        ],
        events: const [],
      );

      // A large count condenses instead of overflowing its third.
      expect(find.text('37.9K'), findsOneWidget);

      // Each figure sits centered above its label. The thirds themselves are
      // Expanded, so their equal widths come from the framework.
      final tiles = find.byType(HeroStatTile);
      for (var i = 0; i < tiles.evaluate().length; i++) {
        final texts = find.descendant(
          of: tiles.at(i),
          matching: find.byType(Text),
        );
        expect(
          tester.getCenter(texts.first).dx,
          moreOrLessEquals(tester.getCenter(texts.last).dx, epsilon: 1),
        );
      }
    });

    testWidgets('renders zeroed tiles with no data at all', (tester) async {
      await pumpScreen(tester, sessions: const [], events: const []);

      expect(find.byType(HeroStatTile), findsNWidgets(3));
      expect(inHero('0m'), findsOneWidget);
      expect(inHero('0'), findsNWidgets(2));
    });

    testWidgets('survives every period with no data at all', (tester) async {
      // The You tab makes this screen reachable before anything has been read,
      // so the empty-data path is reachable in every period rather than only
      // in whichever one happens to be selected first. The charts below the
      // tiles have to cope with zero points, notably the vocabulary line under
      // "All", whose window has no start date to anchor to.
      await pumpScreen(tester, sessions: const [], events: const []);

      for (final period in const ['Week', 'Month', 'Year', 'All']) {
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<StatsPeriod>),
            matching: find.text(period),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'period $period');
        expect(find.byType(HeroStatTile), findsNWidgets(3), reason: period);
        expect(inHero('0m'), findsOneWidget, reason: period);
        expect(inHero('0'), findsNWidgets(2), reason: period);
      }
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
          session(
            id: 1,
            startedAt: now,
            bookFormat: 'epub',
            durationMs: 60 * 60 * 1000,
          ),
          session(
            id: 2,
            startedAt: now,
            bookFormat: 'manga',
            durationMs: 30 * 60 * 1000,
          ),
        ],
        events: const [],
      );
      expect(inHero('1h 30m'), findsOneWidget);

      // "Manga" also names a series in the reading-time card's legend now.
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<StatsFormat>),
          matching: find.text('Manga'),
        ),
      );
      await tester.pumpAndSettle();

      expect(inHero('30m'), findsOneWidget);
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
          wordEvent(id: 1, expression: '本', createdAt: lastYear),
          // Same expression again this week: already counted, not a new word.
          wordEvent(id: 2, expression: '本', createdAt: now),
          wordEvent(id: 3, expression: '猫', createdAt: now),
        ],
      );

      // Week: only 猫 is new.
      expect(inHero('1'), findsOneWidget);

      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();

      // All: both distinct expressions, including the one predating any
      // session.
      expect(inHero('2'), findsOneWidget);
    });

    testWidgets('opens a day detail sheet from a heatmap cell', (tester) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        sessions: [
          session(
            id: 1,
            startedAt: now,
            durationMs: 60 * 60 * 1000,
            charactersRead: 1200,
            lookups: 7,
          ),
        ],
        events: const [],
      );

      await tester.ensureVisible(find.byType(ActivityHeatmapCard));
      await tester.pumpAndSettle();

      // Today's cell is the last one of the rightmost column, and the grid
      // opens scrolled to that end.
      final grid = tester.getRect(find.byKey(ActivityHeatmapCard.gridKey));
      await tester.tapAt(
        Offset(grid.right - 5.5, grid.top + now.weekday % 7 * 14.0 + 5.5),
      );
      await tester.pumpAndSettle();

      Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      expect(inSheet('Reading time'), findsOneWidget);
      expect(inSheet('1h 0m'), findsOneWidget);
      expect(inSheet('1,200'), findsOneWidget);
      expect(inSheet('Lookups'), findsOneWidget);
      expect(inSheet('7'), findsOneWidget);
    });
  });
}
