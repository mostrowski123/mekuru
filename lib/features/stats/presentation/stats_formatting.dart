import 'package:intl/intl.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

/// Splits a duration in milliseconds into the hour and minute parts the stats
/// surfaces render.
///
/// Hours are never rolled up into days — an all-time total splits to
/// `(hours: 30, minutes: 5)`, which is the figure people expect on a reading
/// tile. Sub-minute leftovers floor rather than round up, and negative input (a
/// clock change that slipped past the aggregator's clamping) clamps to zero
/// rather than producing a minus sign.
///
/// Kept separate from [formatDuration] so the arithmetic stays testable without
/// a localizations object.
({int hours, int minutes}) splitDuration(int ms) {
  final totalMinutes = (ms < 0 ? 0 : ms) ~/ Duration.millisecondsPerMinute;
  return (
    hours: totalMinutes ~/ Duration.minutesPerHour,
    minutes: totalMinutes % Duration.minutesPerHour,
  );
}

/// Formats a duration in milliseconds the way the stats surfaces show it:
/// `"0m"`, `"42m"`, `"3h 20m"` in English.
///
/// Shared by the hero tiles, the heatmap's day sheet and the reading-time
/// chart's tooltips, so they never disagree. Below an hour the
/// minutes-only string carries it, zero included; at an hour and above the
/// hour part joins, and whole hours keep the minute part (`"2h 0m"`) so the
/// string does not change shape mid count-up.
///
/// Both shapes come from ARB messages, so a locale that writes durations
/// differently — Japanese and Chinese suffix their own unit characters and drop
/// the space — reorders or replaces the unit markers in its own translation
/// rather than here.
String formatDuration(AppLocalizations l10n, int ms) {
  final split = splitDuration(ms);
  return split.hours == 0
      ? l10n.statsDurationMinutes(minutes: split.minutes)
      : l10n.statsDurationHoursMinutes(
          hours: split.hours,
          minutes: split.minutes,
        );
}

/// The count below which the hero tiles stay exact.
const int _compactCountFloor = 10000;

/// Picks the one representation [finalValue] needs — exact with grouping
/// below five digits ("9,999"), condensed with at most one decimal from
/// there up ("37.9K", "1.2M") — and returns it as a closure.
///
/// The decision is made from the final value rather than per call so a
/// count-up animation renders every frame in the same representation ("9.8K"
/// on the way to "37.9K", never "9,876" flipping to "10K" mid-flight), and so
/// the NumberFormat is parsed once rather than once per frame.
///
/// CLDR's compact patterns carry the per-locale unit systems — Chinese
/// condenses into ten-thousand-based units, for example — so this stays a
/// thin wrapper rather than a hand-rolled suffix table.
String Function(int value) compactCountFormatter(
  String locale,
  int finalValue,
) {
  final format = finalValue < _compactCountFloor
      ? NumberFormat.decimalPattern(locale)
      : (NumberFormat.compact(locale: locale)..maximumFractionDigits = 1);
  return (value) => format.format(value);
}

/// One-shot [compactCountFormatter]: formats [value] as its own final value.
String formatCompactCount(String locale, int value) =>
    compactCountFormatter(locale, value)(value);
