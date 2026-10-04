import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/main.dart' show databaseProvider;
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
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryRepositoryProvider.overrideWithValue(
            DictionaryRepository(db),
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

class _ParsingImportNotifier extends DictionaryImportNotifier {
  @override
  DictionaryImportState build() => const DictionaryImportState(
    isImporting: true,
    currentDictionary: 'Parsing collection…',
  );
}
