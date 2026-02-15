import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';

/// Result of parsing Yomitan term bank files inside an isolate.
class YomitanParseResult {
  final String dictionaryName;
  final List<DictionaryEntriesCompanion> entries;

  YomitanParseResult({required this.dictionaryName, required this.entries});
}

/// Data passed into the isolate for parsing.
class _IsolatePayload {
  final Uint8List zipBytes;

  _IsolatePayload(this.zipBytes);
}

/// Service responsible for importing Yomitan dictionary zip files.
class DictionaryImporter {
  final DictionaryRepository _repository;

  DictionaryImporter(this._repository);

  /// Import a Yomitan dictionary from a zip file path.
  ///
  /// Returns the total number of entries imported.
  /// [onProgress] is called with (processedEntries, totalEntries) during batch insert.
  Future<int> importFromFile(
    String filePath, {
    void Function(int processed, int total)? onProgress,
  }) async {
    // Read the file bytes
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Dictionary file not found', filePath);
    }
    final zipBytes = await file.readAsBytes();

    // Parse in isolate to avoid UI freeze
    final parseResult = await Isolate.run(
      () => _parseZipInIsolate(_IsolatePayload(zipBytes)),
    );

    // Insert dictionary metadata
    final dictionaryId = await _repository.insertDictionary(
      parseResult.dictionaryName,
    );

    // Assign the dictionaryId to all entries
    final entriesWithId = parseResult.entries.map((entry) {
      return entry.copyWith(dictionaryId: Value(dictionaryId));
    }).toList();

    // Batch insert entries with progress reporting
    int totalInserted = 0;
    const batchSize = 10000;
    for (var i = 0; i < entriesWithId.length; i += batchSize) {
      final end = (i + batchSize < entriesWithId.length)
          ? i + batchSize
          : entriesWithId.length;
      final batch = entriesWithId.sublist(i, end);

      await _repository.batchInsertEntries(batch, batchSize: batch.length);
      totalInserted += batch.length;
      onProgress?.call(totalInserted, entriesWithId.length);
    }

    return totalInserted;
  }

  /// Parse a Yomitan zip file on an isolate.
  /// This is a top-level-compatible static function.
  static YomitanParseResult _parseZipInIsolate(_IsolatePayload payload) {
    final archive = ZipDecoder().decodeBytes(payload.zipBytes);

    // 1. Parse index.json for dictionary name
    String dictionaryName = 'Unknown Dictionary';
    final indexFile = archive.findFile('index.json');
    if (indexFile != null) {
      final indexContent = utf8.decode(indexFile.content as List<int>);
      final indexJson = jsonDecode(indexContent) as Map<String, dynamic>;
      dictionaryName = (indexJson['title'] as String?) ?? 'Unknown Dictionary';
    }

    // 2. Parse all term_bank_*.json files
    final entries = <DictionaryEntriesCompanion>[];

    final termBankFiles = archive.files
        .where(
          (f) => f.name.startsWith('term_bank_') && f.name.endsWith('.json'),
        )
        .toList();

    for (final termBank in termBankFiles) {
      final content = utf8.decode(termBank.content as List<int>);
      final termArray = jsonDecode(content) as List<dynamic>;

      for (final term in termArray) {
        if (term is! List || term.length < 6) continue;

        // Yomitan schema:
        // [0] expression (String)
        // [1] reading (String)
        // [2] definition_tags (String) — ignored
        // [3] rules (String) — ignored
        // [4] score (int) — ignored
        // [5] glossary (List/mixed) — we convert to List<String>
        // [6] sequence (int) — ignored
        // [7] term_tags (String) — ignored

        final expression = term[0]?.toString() ?? '';
        final reading = term[1]?.toString() ?? '';

        // Glossary can be a list of strings or a list of complex objects.
        // We stringify everything into a flat list.
        final rawGlossary = term[5];
        final glossaryList = <String>[];
        if (rawGlossary is List) {
          for (final item in rawGlossary) {
            if (item is String) {
              glossaryList.add(item);
            } else if (item is Map) {
              // Some Yomitan dicts use structured glossary objects
              glossaryList.add(jsonEncode(item));
            } else {
              glossaryList.add(item.toString());
            }
          }
        }

        if (expression.isEmpty) continue;

        entries.add(
          DictionaryEntriesCompanion.insert(
            expression: expression,
            reading: Value(reading),
            glossaries: jsonEncode(glossaryList),
            dictionaryId: 0, // Placeholder — will be replaced after insert
          ),
        );
      }
    }

    return YomitanParseResult(dictionaryName: dictionaryName, entries: entries);
  }
}
