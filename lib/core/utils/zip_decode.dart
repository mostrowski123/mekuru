import 'package:archive/archive.dart';

/// The zip read from [input]. ZipDecoder reads anything that isn't a zip (a
/// captive portal's page, an error page served with 200, a download cut off
/// before the zip's end) as an empty archive; this throws a
/// [FormatException] instead.
Archive decodeZip(InputStream input) {
  final archive = ZipDecoder().decodeStream(input);
  if (archive.isEmpty) throw const FormatException('Not a zip file');
  return archive;
}
