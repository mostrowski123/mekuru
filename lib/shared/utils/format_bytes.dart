/// Human-readable byte count: `512 B`, `1.5 KB`, `150 MB`, `5.0 GB`.
///
/// Binary units, one decimal below 100, none above: precise enough for a
/// backup size, short enough for a snackbar.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final number = value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$number ${units[unit]}';
}
