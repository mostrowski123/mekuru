/// Formats a duration in milliseconds the way the stats surfaces show it:
/// `"0m"`, `"42m"`, `"3h 20m"`.
///
/// Shared by the hero tiles, the heatmap's day sheet, the library strip and the
/// reading-time chart's tooltips, so they never disagree. Hours are never
/// rolled up into days — an all-time total reads `"30h 5m"`, which is the
/// figure people expect on a reading tile. Whole hours keep the minute part
/// (`"2h 0m"`) so the string does not change shape mid count-up. Negative input
/// (a clock change that slipped past the aggregator's clamping) reads `"0m"`
/// rather than a minus sign.
String formatDuration(int ms) {
  final totalMinutes = (ms < 0 ? 0 : ms) ~/ Duration.millisecondsPerMinute;
  final hours = totalMinutes ~/ Duration.minutesPerHour;
  final minutes = totalMinutes % Duration.minutesPerHour;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}
