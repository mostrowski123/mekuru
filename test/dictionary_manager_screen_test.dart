import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_database.dart';
import 'test_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
  });

  tearDown(() => db.close());

  Future<void> pumpManager(
    WidgetTester tester,
    List<DictionaryMeta> dictionaries, {
    List<Override> overrides = const [],
    DictionaryRepository? repository,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryRepositoryProvider.overrideWithValue(
            repository ?? DictionaryRepository(db),
          ),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
          ...overrides,
        ],
        child: buildLocalizedTestApp(home: const DictionaryManagerScreen()),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  DictionaryMeta meta(int id, String name, {String? revision}) =>
      DictionaryMeta(
        id: id,
        name: name,
        isEnabled: true,
        dateImported: DateTime(2026, 10, 4),
        sortOrder: id,
        isHidden: false,
        revision: revision,
      );

  testWidgets('dictionaries show their display name and version', (
    tester,
  ) async {
    await pumpManager(tester, [
      meta(1, 'Jitendex.org [2026-10-03]', revision: '2026.10.03.0'),
      meta(2, 'wty-ja-en', revision: '2026.10.02'),
      meta(3, 'My Dictionary'),
    ]);

    expect(find.text('Jitendex'), findsOneWidget);
    expect(
      find.text('Imported 2026-10-04 · version 2026-10-03'),
      findsOneWidget,
    );
    expect(find.text('Wiktionary (English)'), findsOneWidget);
    expect(
      find.text('Imported 2026-10-04 · version 2026.10.02'),
      findsOneWidget,
    );
    expect(find.text('My Dictionary'), findsOneWidget);
    expect(find.text('Imported 2026-10-04'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete "Jitendex"'), findsOneWidget);
  });

  testWidgets('a deleted dictionary leaves while later deletes still run', (
    tester,
  ) async {
    // The list stream stays stale, as Drift's does while deletes queue.
    final repo = _GatedDeleteRepository(db);
    await pumpManager(tester, [
      meta(1, 'First'),
      meta(2, 'Second'),
    ], repository: repo);

    for (var i = 0; i < 2; i++) {
      // The first row's delete button is a spinner now, so .last is next.
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      // Spinners never settle; give the dialog time to open and close.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Delete'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    repo.gates[2]!.complete();
    await tester.pump();

    expect(find.text('Second'), findsNothing);
    expect(find.text('First'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('in Japanese, an import says what happened, never an '
      "error's text", (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final dir = Directory.systemTemp.createTempSync('dictionary_import_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dictionariesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: const DictionaryManagerScreen(),
          locale: const Locale('ja'),
        ),
      ),
    );
    await tester.pump();
    Future<void> import(String name, List<int> bytes) async {
      final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
      await tester.runAsync(
        () => container
            .read(dictionaryImportProvider.notifier)
            .importDictionary(file.path),
      );
      await tester.pump();
    }

    // A collection export cut off midway.
    await import('broken.json', utf8.encode('{"data": [{"tableName": '));
    expect(find.text(ja.dictionaryImportUnreadable), findsOneWidget);
    expect(find.textContaining(RegExp('Exception|Error|data')), findsNothing);

    final index = utf8.encode(jsonEncode({'title': 'Mine', 'format': 3}));
    final bank = utf8.encode(
      jsonEncode([
        [
          '山',
          'やま',
          '',
          '',
          0,
          ['mountain'],
          1,
          '',
        ],
      ]),
    );
    await import(
      'mine.zip',
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile('index.json', index.length, index))
          ..addFile(ArchiveFile('term_bank_1.json', bank.length, bank)),
      ),
    );
    expect(find.text(ja.dictionaryImportedEntries(count: 1)), findsOneWidget);
    expect(find.text(ja.dictionaryImportUnreadable), findsNothing);
  });

  testWidgets('a collection being read shows its banner text once', (
    tester,
  ) async {
    await pumpManager(
      tester,
      [meta(1, 'JMdict [2026-09-01]')],
      overrides: [
        dictionaryImportProvider.overrideWith(_ParsingImportNotifier.new),
      ],
      settle: false,
    );

    expect(find.text('Parsing collection…'), findsOneWidget);
  });
}

class _GatedDeleteRepository extends DictionaryRepository {
  _GatedDeleteRepository(super.db);

  final gates = <int, Completer<void>>{};

  @override
  Future<void> deleteDictionary(int dictionaryId) =>
      (gates[dictionaryId] = Completer<void>()).future;
}

class _ParsingImportNotifier extends DictionaryImportNotifier {
  @override
  DictionaryImportState build() => const DictionaryImportState(
    isImporting: true,
    step: DictionaryImportStep.parsingCollection,
  );
}
