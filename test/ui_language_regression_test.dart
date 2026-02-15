import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'user-facing app shell and presentation files do not contain Japanese script',
    () {
      final japaneseScript = RegExp(
        r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]',
      );
      final presentationSegment = '${p.separator}presentation${p.separator}';

      final filesToCheck = <File>[
        File(p.join('lib', 'app.dart')),
        ...Directory(p.join('lib', 'features'))
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.dart') &&
                  file.path.contains(presentationSegment),
            ),
      ];

      for (final file in filesToCheck) {
        final content = file.readAsStringSync();
        expect(
          japaneseScript.hasMatch(content),
          isFalse,
          reason: 'Japanese text found in ${file.path}',
        );
      }
    },
  );
}
