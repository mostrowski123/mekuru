import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    List<DictionaryMeta> dictionaries,
  ) async {
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
        ],
        child: buildLocalizedTestApp(home: const DictionaryManagerScreen()),
      ),
    );
    await tester.pumpAndSettle();
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
}
