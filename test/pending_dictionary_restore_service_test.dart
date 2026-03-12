import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/pending_dictionary_restore_service.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late DictionaryRepository repository;
  late PendingDictionaryRestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    repository = DictionaryRepository(db);
    service = PendingDictionaryRestoreService();
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'queueFromBackup stores pending snapshot without mutating dictionaries',
    () async {
      final alphaId = await repository.insertDictionary('Alpha');
      await repository.insertDictionary('Beta');
      await repository.toggleDictionary(alphaId, isEnabled: false);

      final result = await service.queueFromBackup(
        preferences: const [
          BackupDictionaryPreference(
            name: 'Beta',
            sortOrder: 0,
            isEnabled: false,
          ),
          BackupDictionaryPreference(
            name: 'Alpha',
            sortOrder: 1,
            isEnabled: true,
          ),
          BackupDictionaryPreference(
            name: 'Missing',
            sortOrder: 2,
            isEnabled: true,
          ),
        ],
        shouldQueue: true,
        repository: repository,
      );

      final dictionaries = await repository.getAllDictionaries();
      expect(dictionaries.map((dictionary) => dictionary.name).toList(), [
        'Alpha',
        'Beta',
      ]);
      expect(dictionaries.first.isEnabled, isFalse);
      expect(result.queued, isTrue);
      expect(result.matchingCount, 2);
      expect(result.missingCount, 1);
      expect(await service.loadPendingRestore(), isNotNull);
    },
  );

  test(
    'queueFromBackup with shouldQueue false clears existing snapshot',
    () async {
      await repository.insertDictionary('Alpha');
      await service.savePendingRestore(const [
        BackupDictionaryPreference(
          name: 'Alpha',
          sortOrder: 0,
          isEnabled: true,
        ),
      ]);

      final result = await service.queueFromBackup(
        preferences: const [
          BackupDictionaryPreference(
            name: 'Alpha',
            sortOrder: 0,
            isEnabled: true,
          ),
        ],
        shouldQueue: false,
        repository: repository,
      );

      expect(result.skipped, isTrue);
      expect(await service.loadPendingRestore(), isNull);
    },
  );

  test(
    'applyPendingRestore updates matched dictionaries and clears snapshot',
    () async {
      await repository.insertDictionary('Unmatched');
      final alphaId = await repository.insertDictionary('Alpha');
      final betaId = await repository.insertDictionary('Beta');
      await repository.toggleDictionary(alphaId, isEnabled: true);
      await repository.toggleDictionary(betaId, isEnabled: false);

      await service.savePendingRestore(const [
        BackupDictionaryPreference(name: 'Beta', sortOrder: 0, isEnabled: true),
        BackupDictionaryPreference(
          name: 'Missing',
          sortOrder: 1,
          isEnabled: true,
        ),
        BackupDictionaryPreference(
          name: 'Alpha',
          sortOrder: 2,
          isEnabled: false,
        ),
      ]);

      final result = await service.applyPendingRestore(repository);
      final dictionaries = await repository.getAllDictionaries();

      expect(result.appliedCount, 2);
      expect(result.missingCount, 1);
      expect(dictionaries.map((dictionary) => dictionary.name).toList(), [
        'Beta',
        'Alpha',
        'Unmatched',
      ]);
      expect(
        dictionaries
            .firstWhere((dictionary) => dictionary.name == 'Beta')
            .isEnabled,
        isTrue,
      );
      expect(
        dictionaries
            .firstWhere((dictionary) => dictionary.name == 'Alpha')
            .isEnabled,
        isFalse,
      );
      expect(await service.loadPendingRestore(), isNull);
    },
  );

  test(
    'applyPendingRestore with zero matches keeps snapshot pending',
    () async {
      await repository.insertDictionary('Installed');
      await service.savePendingRestore(const [
        BackupDictionaryPreference(
          name: 'Missing',
          sortOrder: 0,
          isEnabled: true,
        ),
      ]);

      final result = await service.applyPendingRestore(repository);

      expect(result.appliedCount, 0);
      expect(result.missingCount, 1);
      expect(await service.loadPendingRestore(), isNotNull);
    },
  );
}
