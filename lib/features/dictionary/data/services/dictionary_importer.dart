import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:json_events/json_events.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';

/// Result of parsing Yomitan term bank files inside an isolate.
class YomitanParseResult {
  final String dictionaryName;
  final List<DictionaryEntriesCompanion> entries;

  YomitanParseResult({required this.dictionaryName, required this.entries});
}

/// Summary of a collection import operation.
class CollectionImportResult {
  final List<String> importedDictionaries;
  final List<String> skippedDictionaries;
  final int totalEntriesImported;

  CollectionImportResult({
    required this.importedDictionaries,
    required this.skippedDictionaries,
    required this.totalEntriesImported,
  });
}

/// Data passed into the isolate for parsing.
class _IsolatePayload {
  final Uint8List zipBytes;

  _IsolatePayload(this.zipBytes);
}

// Isolate message protocol for collection parsing.
// We use simple types (String, List, Map) that can cross isolate boundaries.
//
// Messages from worker → main:
//   ['batch', List<Map<String, String>>]  — a batch of parsed terms
//   ['done']                              — parsing complete
//   ['error', String]                     — parsing failed

/// Service responsible for importing Yomitan dictionary files.
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

  /// Import a Yomitan dictionary collection from a Dexie JSON export.
  ///
  /// Uses streaming JSON parsing (json_events) to handle files of any size
  /// without loading the entire file into memory. The file is parsed in a
  /// separate isolate which streams batches of entries back via SendPort.
  ///
  /// Callbacks:
  /// - [onParsing] called when isolate parsing begins
  /// - [onDictionaryStart] called when starting to insert a dictionary
  /// - [onProgress] called with (processedEntries, totalEntries) per dictionary
  /// - [onDictionarySkipped] called when a dictionary is skipped (already exists)
  Future<CollectionImportResult> importCollectionFromFile(
    String filePath, {
    void Function()? onParsing,
    void Function(String name, int entryCount, int dictIndex, int dictTotal)?
        onDictionaryStart,
    void Function(int processed, int total)? onProgress,
    void Function(String name)? onDictionarySkipped,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Collection file not found', filePath);
    }

    onParsing?.call();

    // Collect terms streamed from the isolate, grouped by dictionary name.
    // Each entry is a lightweight map with pre-encoded glossaries JSON.
    final entriesByDict = <String, List<Map<String, String>>>{};

    // Set up isolate communication
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _streamParseCollection,
      [receivePort.sendPort, filePath],
    );

    // Listen for batches from the isolate
    String? errorMessage;
    await for (final message in receivePort) {
      final msg = message as List;
      final type = msg[0] as String;

      if (type == 'batch') {
        final terms = msg[1] as List;
        for (final term in terms) {
          final t = term as Map<String, String>;
          final dictName = t['dictionary']!;
          entriesByDict.putIfAbsent(dictName, () => []).add(t);
        }
      } else if (type == 'done') {
        break;
      } else if (type == 'error') {
        errorMessage = msg[1] as String;
        break;
      }
    }
    receivePort.close();

    if (errorMessage != null) {
      throw FormatException(errorMessage);
    }

    // Insert each dictionary into the DB
    final dictNames = entriesByDict.keys.toList();
    final importedDicts = <String>[];
    final skippedDicts = <String>[];
    int totalEntriesImported = 0;

    for (var i = 0; i < dictNames.length; i++) {
      final dictName = dictNames[i];
      final rawEntries = entriesByDict[dictName]!;

      // Check if dictionary already exists
      final existing = await _repository.getDictionaryByName(dictName);
      if (existing != null) {
        skippedDicts.add(dictName);
        onDictionarySkipped?.call(dictName);
        continue;
      }

      onDictionaryStart?.call(dictName, rawEntries.length, i, dictNames.length);

      // Insert dictionary metadata
      final dictionaryId = await _repository.insertDictionary(dictName);

      // Convert to DictionaryEntriesCompanion and batch insert
      int inserted = 0;
      const batchSize = 10000;
      for (var j = 0; j < rawEntries.length; j += batchSize) {
        final end = (j + batchSize < rawEntries.length)
            ? j + batchSize
            : rawEntries.length;

        final batch = rawEntries.sublist(j, end).map((raw) {
          return DictionaryEntriesCompanion.insert(
            expression: raw['expression']!,
            reading: Value(raw['reading'] ?? ''),
            glossaries: raw['glossaries']!,
            dictionaryId: dictionaryId,
          );
        }).toList();

        await _repository.batchInsertEntries(batch, batchSize: batch.length);
        inserted += batch.length;
        onProgress?.call(inserted, rawEntries.length);
      }

      totalEntriesImported += inserted;
      importedDicts.add(dictName);
    }

    return CollectionImportResult(
      importedDictionaries: importedDicts,
      skippedDictionaries: skippedDicts,
      totalEntriesImported: totalEntriesImported,
    );
  }

  /// Isolate entry point for streaming collection parsing.
  ///
  /// Opens the file as a byte stream, uses json_events for SAX-style parsing,
  /// and sends batches of parsed term entries back via SendPort.
  /// Only the file path is passed in — no large data crosses the isolate boundary.
  static Future<void> _streamParseCollection(List args) async {
    final sendPort = args[0] as SendPort;
    final filePath = args[1] as String;

    try {
      final eventStream = File(filePath)
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const JsonEventDecoder())
          .flatten();

      // State machine for navigating the Dexie JSON structure.
      //
      // Target structure:
      // { "data": { "data": [
      //   { "tableName": "terms", "rows": [
      //     { "expression": "...", "reading": "...",
      //       "glossary": [...], "dictionary": "..." },
      //     ...
      //   ]}
      // ]}}

      int depth = 0;

      // Track data.data array
      bool inDataDataArray = false;
      int dataDataDepth = 0;

      // Track table objects within data.data
      bool inTableObject = false;
      int tableObjectDepth = 0;
      String? currentTableName;

      // Track terms rows array
      bool inTermsRows = false;
      int termsRowsDepth = 0;

      // Track individual term object
      bool inTermObject = false;
      int termObjectDepth = 0;
      String? currentKey;
      String? termExpression;
      String? termReading;
      String? termDictionary;
      List<dynamic>? termGlossary;

      // Track glossary array within a term.
      //
      // When we encounter a non-primitive value (object or array) inside
      // the glossary array, we capture it by reconstructing valid JSON in
      // a StringBuffer. A stack (capNeedsComma) tracks whether a comma
      // is needed before the next value at each nesting level.
      bool inGlossaryArray = false;
      int glossaryDepth = 0;
      int capNesting = 0; // capture depth (>0 means we're reconstructing)
      StringBuffer? capBuf;
      final capNeedsComma = <bool>[]; // stack: needs comma before next item
      bool capClosedStructure = false; // set after endObject/endArray

      // Property navigation
      String? pendingPropertyName;

      // Batch accumulation
      final batch = <Map<String, String>>[];
      const batchSize = 5000;

      await for (final event in eventStream) {
        switch (event.type) {
          case JsonEventType.beginObject:
            depth++;
            if (inGlossaryArray && capNesting > 0) {
              // Nested object inside a captured structure
              if (capNeedsComma.isNotEmpty && capNeedsComma.last) {
                capBuf?.write(',');
              }
              capBuf?.write('{');
              capNesting++;
              capNeedsComma.add(false); // new level, no comma needed yet
              capClosedStructure = false;
            } else if (inGlossaryArray && capNesting == 0) {
              // Top-level object in glossary array — start capturing
              capBuf = StringBuffer('{');
              capNesting = 1;
              capNeedsComma.clear();
              capNeedsComma.add(false);
              capClosedStructure = false;
            } else if (inTermsRows &&
                !inTermObject &&
                depth == termsRowsDepth + 1) {
              // Starting a new term object
              inTermObject = true;
              termObjectDepth = depth;
              termExpression = null;
              termReading = null;
              termDictionary = null;
              termGlossary = null;
            } else if (inDataDataArray &&
                !inTableObject &&
                !inTermsRows &&
                depth == dataDataDepth + 1) {
              // Starting a new table object
              inTableObject = true;
              tableObjectDepth = depth;
              currentTableName = null;
            }

          case JsonEventType.endObject:
            if (inGlossaryArray && capNesting > 0) {
              capBuf?.write('}');
              capNesting--;
              if (capNeedsComma.isNotEmpty) capNeedsComma.removeLast();
              if (capNesting == 0) {
                // Finished capturing a top-level glossary object
                termGlossary?.add(capBuf.toString());
                capBuf = null;
                capNeedsComma.clear();
              } else {
                // Mark that the parent level now needs a comma before next
                capClosedStructure = true;
                if (capNeedsComma.isNotEmpty) capNeedsComma.last = true;
              }
            } else if (inTermObject && depth == termObjectDepth) {
              // Finished a term object — emit it
              if (termExpression != null && termExpression.isNotEmpty) {
                final glossaryList = <String>[];
                if (termGlossary != null) {
                  for (final item in termGlossary) {
                    if (item is String) {
                      glossaryList.add(item);
                    } else {
                      glossaryList.add(item.toString());
                    }
                  }
                }

                batch.add({
                  'expression': termExpression,
                  'reading': termReading ?? '',
                  'dictionary': termDictionary ?? 'Unknown Dictionary',
                  'glossaries': jsonEncode(glossaryList),
                });

                if (batch.length >= batchSize) {
                  sendPort.send(['batch', List<Map<String, String>>.of(batch)]);
                  batch.clear();
                }
              }
              inTermObject = false;
            } else if (inTableObject && depth == tableObjectDepth) {
              inTableObject = false;
              currentTableName = null;
            }
            depth--;

          case JsonEventType.beginArray:
            depth++;
            if (inGlossaryArray && capNesting > 0) {
              // Nested array inside a captured structure
              if (capNeedsComma.isNotEmpty && capNeedsComma.last) {
                capBuf?.write(',');
              }
              capBuf?.write('[');
              capNesting++;
              capNeedsComma.add(false);
              capClosedStructure = false;
            } else if (inTermObject && currentKey == 'glossary') {
              inGlossaryArray = true;
              glossaryDepth = depth;
              capNesting = 0;
              capBuf = null;
              capNeedsComma.clear();
              capClosedStructure = false;
              termGlossary = [];
            } else if (inTableObject &&
                currentTableName == 'terms' &&
                pendingPropertyName == 'rows') {
              inTermsRows = true;
              termsRowsDepth = depth;
              pendingPropertyName = null;
            } else if (!inDataDataArray && pendingPropertyName == 'data') {
              // Heuristic: the inner "data" array (data.data)
              inDataDataArray = true;
              dataDataDepth = depth;
              pendingPropertyName = null;
            }

          case JsonEventType.endArray:
            if (inGlossaryArray && capNesting > 0) {
              capBuf?.write(']');
              capNesting--;
              if (capNeedsComma.isNotEmpty) capNeedsComma.removeLast();
              if (capNesting == 0) {
                // Finished capturing a top-level glossary array
                termGlossary?.add(capBuf.toString());
                capBuf = null;
                capNeedsComma.clear();
              } else {
                capClosedStructure = true;
                if (capNeedsComma.isNotEmpty) capNeedsComma.last = true;
              }
            } else if (inGlossaryArray && depth == glossaryDepth) {
              inGlossaryArray = false;
              capNesting = 0;
              capBuf = null;
              capNeedsComma.clear();
              capClosedStructure = false;
              currentKey = null;
            } else if (inTermsRows && depth == termsRowsDepth) {
              inTermsRows = false;
            } else if (inDataDataArray && depth == dataDataDepth) {
              inDataDataArray = false;
            }
            depth--;

          case JsonEventType.propertyName:
            if (inGlossaryArray && capNesting > 0) {
              if (capNeedsComma.isNotEmpty && capNeedsComma.last) {
                capBuf?.write(',');
              }
              capBuf?.write('${jsonEncode(event.value)}:');
              // After writing property name, no comma before the value
              if (capNeedsComma.isNotEmpty) capNeedsComma.last = false;
              capClosedStructure = false;
            } else if (inTermObject && depth == termObjectDepth) {
              currentKey = event.value as String?;
            } else {
              pendingPropertyName = event.value as String?;
            }

          case JsonEventType.propertyValue:
            if (inGlossaryArray && capNesting > 0) {
              // propertyValue fires after the value's structure events for
              // non-primitive values (objects/arrays). In that case
              // event.value is null and capClosedStructure is true — the
              // JSON was already written by begin/end handlers, so skip.
              if (!capClosedStructure) {
                capBuf?.write(jsonEncode(event.value));
              }
              capClosedStructure = false;
              // Next property in this object needs a leading comma
              if (capNeedsComma.isNotEmpty) capNeedsComma.last = true;
            } else if (inTermObject && depth == termObjectDepth) {
              switch (currentKey) {
                case 'expression':
                  termExpression = event.value?.toString();
                case 'reading':
                  termReading = event.value?.toString();
                case 'dictionary':
                  termDictionary = event.value?.toString();
              }
              currentKey = null;
            } else if (inTableObject &&
                pendingPropertyName == 'tableName' &&
                depth == tableObjectDepth) {
              currentTableName = event.value?.toString();
              pendingPropertyName = null;
            } else {
              pendingPropertyName = null;
            }

          case JsonEventType.arrayElement:
            if (inGlossaryArray && capNesting > 0) {
              // arrayElement fires after structure events for non-primitive
              // values. If capClosedStructure is true, JSON was already
              // written — just mark that next element needs a comma.
              if (!capClosedStructure) {
                if (capNeedsComma.isNotEmpty && capNeedsComma.last) {
                  capBuf?.write(',');
                }
                capBuf?.write(jsonEncode(event.value));
              }
              capClosedStructure = false;
              if (capNeedsComma.isNotEmpty) capNeedsComma.last = true;
            } else if (inGlossaryArray && capNesting == 0) {
              // Plain string/number element at the top level of glossary
              if (event.value != null) {
                termGlossary?.add(event.value);
              }
            }
        }
      }

      // Send remaining batch
      if (batch.isNotEmpty) {
        sendPort.send(['batch', batch]);
      }

      sendPort.send(['done']);
    } catch (e) {
      sendPort.send(['error', e.toString()]);
    }
  }

  /// Parse a Yomitan zip file on an isolate.
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

        final expression = term[0]?.toString() ?? '';
        final reading = term[1]?.toString() ?? '';

        final rawGlossary = term[5];
        final glossaryList = <String>[];
        if (rawGlossary is List) {
          for (final item in rawGlossary) {
            if (item is String) {
              glossaryList.add(item);
            } else if (item is Map) {
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
