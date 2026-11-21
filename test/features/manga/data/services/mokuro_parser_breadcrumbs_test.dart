import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/pii_scrubber.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';

/// In release builds Sentry keeps each debugPrint line as a console
/// breadcrumb, and scrubEvent runs over it before an event is sent. The
/// book's own name may stay; the names of the user's other files and folders
/// may not.
void main() {
  const book = 'Sample Vol 01';
  // What else is in the folder the user imports from.
  const otherNames = [
    'Tax Return 2025',
    'Doctor Letters',
    'Clinic Notes',
    'Bank Statement March',
    'Lease Agreement',
  ];

  late Directory root;
  late List<String> printed;
  late DebugPrintCallback savedDebugPrint;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mokuro_breadcrumbs_');
    for (final dir in [
      book,
      '_ocr/$book',
      'Tax Return 2025',
      'Doctor Letters',
    ]) {
      Directory(p.join(root.path, dir)).createSync(recursive: true);
    }
    File(p.join(root.path, book, '0001.jpg')).writeAsBytesSync([0]);
    File(p.join(root.path, '$book.html')).writeAsStringSync('<html></html>');
    File(p.join(root.path, '$book.mokuro')).writeAsStringSync(
      jsonEncode({
        'title': book,
        'volume': book,
        'pages': [
          {
            'img_path': '0001.jpg',
            'img_width': 10,
            'img_height': 20,
            'blocks': [],
          },
        ],
      }),
    );
    File(p.join(root.path, 'Clinic Notes.html')).writeAsStringSync('');
    File(p.join(root.path, 'Bank Statement March.pdf')).writeAsBytesSync([0]);
    File(p.join(root.path, 'Lease Agreement')).writeAsBytesSync([0]);

    savedDebugPrint = debugPrint;
    printed = [];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });

  tearDown(() {
    debugPrint = savedDebugPrint;
    root.deleteSync(recursive: true);
  });

  /// [line] as Sentry sends it, scrubbed.
  String asBreadcrumb(String line) => scrubEvent(
    SentryEvent(breadcrumbs: [Breadcrumb.console(message: line)]),
    Hint(),
  ).breadcrumbs!.single.message!;

  List<String> breadcrumbsNamingOtherFiles() => [
    for (final line in printed.map(asBreadcrumb))
      if (otherNames.any(line.contains)) line,
  ];

  test('importing a mokuro HTML file names no other file or folder', () async {
    await MokuroParser.parseSingleHtmlFile(p.join(root.path, '$book.html'));

    expect(printed, isNotEmpty);
    expect(breadcrumbsNamingOtherFiles(), isEmpty);
  });

  test('importing a .mokuro file names no other file or folder', () async {
    await MokuroParser.parseMokuroFile(p.join(root.path, '$book.mokuro'));

    expect(printed, isNotEmpty);
    expect(breadcrumbsNamingOtherFiles(), isEmpty);
  });
}
