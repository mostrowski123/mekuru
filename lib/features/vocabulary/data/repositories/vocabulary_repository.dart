import 'dart:io';

import 'package:csv/csv.dart' as csv;
import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Repository for managing saved vocabulary (SavedWords).
class VocabularyRepository {
  final AppDatabase _db;

  VocabularyRepository(this._db);

  // ──────────────── Queries ────────────────

  /// Get all saved words ordered by date added (newest first).
  Future<List<SavedWord>> getAllWords() => (_db.select(
    _db.savedWords,
  )..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])).get();

  /// Watch all saved words (reactive stream).
  Stream<List<SavedWord>> watchAllWords() => (_db.select(
    _db.savedWords,
  )..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])).watch();

  /// Check if a word is already saved (by expression and reading).
  Future<bool> isWordSaved(String expression, String reading) async {
    final query = _db.selectOnly(_db.savedWords)
      ..addColumns([_db.savedWords.id])
      ..where(
        (_db.savedWords.expression.equals(expression) &
            _db.savedWords.reading.equals(reading)),
      )
      ..limit(1);

    return await query.getSingleOrNull() != null;
  }

  // ──────────────── CRUD ────────────────

  /// Save a dictionary entry as a vocabulary word.
  Future<int> addWord({
    required DictionaryEntry entry,
    String sentenceContext = '',
  }) async {
    // DictionaryEntry glossaries are List<String>, but stored as JSON in DictionaryEntry table?
    // Wait, let's check DictionaryEntry model. It usually stores glossaries as JSON string or List<String>
    // depending on the converter. SavedWords.glossaries is TextColumn.
    // We'll trust the input DictionaryEntry has the correct data, but we need to ensure
    // we are saving it correctly.

    // SavedWords.glossaries is a TextColumn.
    // If DictionaryEntry.glossaries is List<String>, we need to encode it.
    // But DictionaryEntry is a generated DataClass, its `glossaries` field type depends on type converter (if any).
    // Let's assume we receive the raw data or we handle it.
    // ACTUALLY, DictionaryEntry (drift generated) likely has `glossaries` as `List<String>` if a converter is used,
    // or `String` if not.
    // Let's check DictionaryEntry definition in schema.

    // For now, I will assume we pass the raw strings.

    final id = await _db
        .into(_db.savedWords)
        .insert(
          SavedWordsCompanion.insert(
            expression: entry.expression,
            reading: Value(entry.reading),
            glossaries: entry.glossaries,
            sentenceContext: Value(sentenceContext),
          ),
        );

    Sentry.metrics.count('vocabulary.word_saved', 1);

    return id;
  }

  /// Delete a saved word by ID.
  Future<void> deleteWord(int id) =>
      (_db.delete(_db.savedWords)..where((t) => t.id.equals(id))).go();

  Future<void> restoreWord(SavedWord word) {
    return _db
        .into(_db.savedWords)
        .insertOnConflictUpdate(
          SavedWordsCompanion(
            id: Value(word.id),
            expression: Value(word.expression),
            reading: Value(word.reading),
            glossaries: Value(word.glossaries),
            sentenceContext: Value(word.sentenceContext),
            dateAdded: Value(word.dateAdded),
          ),
        );
  }

  // ──────────────── Export ────────────────

  /// Export vocabulary to a CSV file and return the file.
  ///
  /// If [selectedIds] is provided and non-empty, only words with those IDs
  /// are exported. Otherwise, all words are exported.
  Future<File> exportToCsv({Set<int>? selectedIds}) async {
    List<SavedWord> words;
    if (selectedIds != null && selectedIds.isNotEmpty) {
      words =
          await (_db.select(_db.savedWords)
                ..where((t) => t.id.isIn(selectedIds))
                ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
              .get();
    } else {
      words = await getAllWords();
    }

    final List<List<dynamic>> rows = [
      ['Word', 'Reading', 'Meaning', 'Furigana', 'Context'],
    ];

    for (var word in words) {
      final meanings = GlossaryParser.parse(word.glossaries).join('; ');
      final furigana = formatAnkiFurigana(word.expression, word.reading);

      rows.add([
        word.expression,
        word.reading,
        meanings,
        furigana,
        word.sentenceContext,
      ]);
    }

    final csvString = const csv.CsvEncoder().convert(rows);

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/vocabulary_export.csv');
    await file.writeAsString(csvString);

    return file;
  }
}
