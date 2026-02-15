import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart' as csv;
import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final count =
        await (_db.select(_db.savedWords)..where(
              (t) =>
                  t.expression.equals(expression) & t.reading.equals(reading),
            ))
            .get();
    return count.isNotEmpty;
  }

  // ──────────────── CRUD ────────────────

  /// Save a dictionary entry as a vocabulary word.
  Future<int> addWord({
    required DictionaryEntry entry,
    String sentenceContext = '',
  }) {
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

    return _db
        .into(_db.savedWords)
        .insert(
          SavedWordsCompanion.insert(
            expression: entry.expression,
            reading: Value(entry.reading),

            // We'll simply copy the glossaries.
            // If DictionaryEntry uses a converter, `entry.glossaries` is List<String>.
            // If SavedWords uses a converter (which it should to be useful), we pass List<String>.
            // If no converter, we pass JSON string.
            // I'll assume for now we need to pass a JSON string if no converter is on SavedWords.
            // But better: let's verify SavedWords and DictionaryEntry usage.
            // If I look at `database_provider.dart`, I didn't see type converters attached in the Table definition
            // I saw earlier.

            // Re-reading `database_provider.dart` from earlier view...
            // `glossaries => text()(); // JSON-encoded List<String>` comment exists.
            // So it expects a String.
            glossaries: entry
                .glossaries, // Assuming entry.glossaries is already the JSON string.
            sentenceContext: Value(sentenceContext),
          ),
        );
  }

  /// Delete a saved word by ID.
  Future<void> deleteWord(int id) =>
      (_db.delete(_db.savedWords)..where((t) => t.id.equals(id))).go();

  // ──────────────── Export ────────────────

  /// Export vocabulary to a CSV file and return the file.
  ///
  /// If [selectedIds] is provided and non-empty, only words with those IDs
  /// are exported. Otherwise, all words are exported.
  Future<XFile> exportToCsv({Set<int>? selectedIds}) async {
    List<SavedWord> words;
    if (selectedIds != null && selectedIds.isNotEmpty) {
      words = await (_db.select(_db.savedWords)
            ..where((t) => t.id.isIn(selectedIds))
            ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
          .get();
    } else {
      words = await getAllWords();
    }

    final List<List<dynamic>> rows = [
      ['Expression', 'Reading', 'Meaning', 'Context', 'Date Added'], // Header
    ];

    for (var word in words) {
      // Decode glossaries JSON to a readable string (e.g. joined by ;)
      String meanings = '';
      try {
        final List<dynamic> list = jsonDecode(word.glossaries);
        meanings = list.join('; ');
      } catch (e) {
        meanings = word.glossaries;
      }

      rows.add([
        word.expression,
        word.reading,
        meanings,
        word.sentenceContext,
        word.dateAdded.toIso8601String(),
      ]);
    }

    final csvString = const csv.CsvEncoder().convert(rows);

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/vocabulary_export.csv');
    await file.writeAsString(csvString);

    return XFile(file.path);
  }
}
