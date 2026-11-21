import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _table = 'test/architecture/README.md';

/// The rule table in [_table] names, in backticks in its second column, the
/// files that fail when a rule is broken. A name without a slash is a
/// workflow in .github/workflows/.
void main() {
  // The rows: the first table in the file, past its header and rule.
  final rows = [
    for (final line
        in File(_table)
            .readAsLinesSync()
            .skipWhile((l) => !l.startsWith('|'))
            .takeWhile((l) => l.startsWith('|'))
            .skip(2))
      line.split('|').map((cell) => cell.trim()).toList(),
  ];

  test('finds the rule table', () {
    expect(
      rows,
      isNotEmpty,
      reason:
          '$_table has no table. If it moved, change the path in '
          'test/architecture/rule_table_test.dart and in CLAUDE.md too.',
    );
  });

  test('CLAUDE.md points at the rule table', () {
    expect(File('CLAUDE.md').readAsStringSync(), contains('`$_table`'));
  });

  test('every file the enforcement column names exists', () {
    final code = RegExp('`([^`]+)`');
    final missing = [
      for (final row in rows)
        for (final m in code.allMatches(row[2]))
          if (FileSystemEntity.typeSync(
                m[1]!.contains('/') ? m[1]! : '.github/workflows/${m[1]}',
              ) ==
              FileSystemEntityType.notFound)
            '`${m[1]}` in the row "${row[1]}" is not in the repo. Fix the '
                'path, or the row if the check is gone. A name without a slash '
                'is read as a workflow in .github/workflows/.',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
