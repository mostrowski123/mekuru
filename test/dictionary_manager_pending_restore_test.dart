import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

class _FakePendingDictionaryRestoreService
    extends PendingDictionaryRestoreService {}

void main() {
  testWidgets(
    'shows pending backup card on Dictionary Manager and warning modal before apply',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryRepositoryProvider.overrideWithValue(
              DictionaryRepository(db),
            ),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value([
                DictionaryMeta(
                  id: 1,
                  name: 'JMdict',
                  isEnabled: true,
                  dateImported: DateTime(2026, 3, 12),
                  sortOrder: 0,
                  isHidden: false,
                ),
              ]),
            ),
            pendingDictionaryRestorePreviewProvider.overrideWith(
              (ref) async => const PendingDictionaryRestorePreview(
                totalCount: 2,
                matchingCount: 1,
                missingCount: 1,
              ),
            ),
            pendingDictionaryRestoreServiceProvider.overrideWithValue(
              _FakePendingDictionaryRestoreService(),
            ),
          ],
          child: buildLocalizedTestApp(home: const DictionaryManagerScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Backup dictionary settings ready'), findsOneWidget);
      expect(find.text('Apply Backup Settings'), findsOneWidget);

      await tester.tap(find.text('Apply Backup Settings'));
      await tester.pumpAndSettle();

      expect(
        find.text('Overwrite current dictionary settings?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('overwrite the current order'),
        findsOneWidget,
      );
    },
  );

  testWidgets('does not show pending backup card on Dictionary Search', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([
              DictionaryMeta(
                id: 1,
                name: 'JMdict',
                isEnabled: true,
                dateImported: DateTime(2026, 3, 12),
                sortOrder: 0,
                isHidden: false,
              ),
            ]),
          ),
          pendingDictionaryRestorePreviewProvider.overrideWith(
            (ref) async => const PendingDictionaryRestorePreview(
              totalCount: 1,
              matchingCount: 1,
              missingCount: 0,
            ),
          ),
        ],
        child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Backup dictionary settings ready'), findsNothing);
    expect(find.text('Apply Backup Settings'), findsNothing);
  });
}
