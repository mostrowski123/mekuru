import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';

void main() {
  test('restoreWord re-inserts a deleted word for undo flows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = VocabularyRepository(db);

    final id = await db
        .into(db.savedWords)
        .insert(
          SavedWordsCompanion.insert(
            expression: '食べる',
            reading: const Value('たべる'),
            glossaries: jsonEncode(['to eat']),
          ),
        );

    final originalWord = (await repo.getAllWords()).single;
    expect(originalWord.id, id);

    await repo.deleteWord(id);
    expect(await repo.getAllWords(), isEmpty);

    await repo.restoreWord(originalWord);

    final restoredWords = await repo.getAllWords();
    expect(restoredWords, hasLength(1));
    expect(restoredWords.single.expression, '食べる');
    expect(restoredWords.single.reading, 'たべる');
  });
}
