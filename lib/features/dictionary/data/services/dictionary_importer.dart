import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:json_events/json_events.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/kanji_reading_parser.dart';

/// Result of parsing Yomitan term bank files inside an isolate.
class YomitanParseResult {
  final String dictionaryName;
  final List<DictionaryEntriesCompanion> entries;
  final List<PitchAccentsCompanion> pitchAccents;
  final List<FrequenciesCompanion> frequencies;

  YomitanParseResult({
    required this.dictionaryName,
    required this.entries,
    this.pitchAccents = const [],
    this.frequencies = const [],
  });
}

/// Summary of a collection import operation.
class CollectionImportResult {
  final List<String> importedDictionaries;
  final List<String> skippedDictionaries;
  final int totalEntriesImported;
  final int totalPitchAccentsImported;
  final int totalFrequenciesImported;

  CollectionImportResult({
    required this.importedDictionaries,
    required this.skippedDictionaries,
    required this.totalEntriesImported,
    this.totalPitchAccentsImported = 0,
    this.totalFrequenciesImported = 0,
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
//   ['batch', List<Map<String, String>>]        — a batch of parsed terms
//   ['pitch_batch', List<Map<String, dynamic>>]  — a batch of parsed pitch accents
//   ['freq_batch', List<Map<String, dynamic>>]   — a batch of parsed frequencies
//   ['done']                                    — parsing complete
//   ['error', String]                           — parsing failed

/// Service responsible for importing Yomitan dictionary files.
class DictionaryImporter {
  final DictionaryRepository _repository;

  DictionaryImporter(this._repository);

  static String _stringifyKanjiReadingSource(dynamic raw) {
    if (raw == null) return '';
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    return raw.toString().trim();
  }

  static List<String> _normalizeKanjiReadings(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .expand((item) => splitKanjiReadingTokens(item.toString()))
          .toList(growable: false);
    }
    return splitKanjiReadingTokens(raw.toString());
  }

  static String _stringifyTagValue(dynamic raw) {
    if (raw == null) return '';
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    return raw.toString().trim();
  }

  static ({int? rank, String reading}) _parseFrequencyData(dynamic data) {
    int? rank;
    var reading = '';

    if (data is int) {
      rank = data;
    } else if (data is num) {
      rank = data.toInt();
    } else if (data is Map) {
      reading = data['reading']?.toString() ?? '';

      final directValue = data['value'];
      if (directValue is int) {
        rank = directValue;
      } else if (directValue is num) {
        rank = directValue.toInt();
      } else {
        final freq = data['frequency'];
        if (freq is int) {
          rank = freq;
        } else if (freq is num) {
          rank = freq.toInt();
        } else if (freq is Map) {
          final val = freq['value'];
          if (val is num) rank = val.toInt();
        }
      }
    }

    return (rank: rank, reading: reading);
  }

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

    // Insert pitch accents if present
    if (parseResult.pitchAccents.isNotEmpty) {
      final pitchWithId = parseResult.pitchAccents.map((p) {
        return p.copyWith(dictionaryId: Value(dictionaryId));
      }).toList();
      await _repository.batchInsertPitchAccents(pitchWithId);
    }

    // Insert frequencies if present
    if (parseResult.frequencies.isNotEmpty) {
      final freqWithId = parseResult.frequencies.map((f) {
        return f.copyWith(dictionaryId: Value(dictionaryId));
      }).toList();
      await _repository.batchInsertFrequencies(freqWithId);
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

    // Collect pitch accents streamed from the isolate, grouped by dictionary name.
    final pitchEntriesByDict = <String, List<Map<String, dynamic>>>{};

    // Collect frequencies streamed from the isolate, grouped by dictionary name.
    final freqEntriesByDict = <String, List<Map<String, dynamic>>>{};

    // Set up isolate communication
    final receivePort = ReceivePort();
    await Isolate.spawn(_streamParseCollection, [
      receivePort.sendPort,
      filePath,
    ]);

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
      } else if (type == 'pitch_batch') {
        final pitches = msg[1] as List;
        for (final pitch in pitches) {
          final p = pitch as Map<String, dynamic>;
          final dictName = p['dictionary'] as String;
          pitchEntriesByDict.putIfAbsent(dictName, () => []).add(p);
        }
      } else if (type == 'freq_batch') {
        final freqs = msg[1] as List;
        for (final freq in freqs) {
          final f = freq as Map<String, dynamic>;
          final dictName = f['dictionary'] as String;
          freqEntriesByDict.putIfAbsent(dictName, () => []).add(f);
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
    // Merge dict names from term entries, pitch accents, and frequencies.
    final allDictNames = <String>{
      ...entriesByDict.keys,
      ...pitchEntriesByDict.keys,
      ...freqEntriesByDict.keys,
    }.toList();
    final importedDicts = <String>[];
    final skippedDicts = <String>[];
    int totalEntriesImported = 0;
    int totalPitchAccentsImported = 0;
    int totalFrequenciesImported = 0;

    for (var i = 0; i < allDictNames.length; i++) {
      final dictName = allDictNames[i];
      final rawEntries = entriesByDict[dictName] ?? [];
      final rawPitchEntries = pitchEntriesByDict[dictName] ?? [];
      final rawFreqEntries = freqEntriesByDict[dictName] ?? [];

      // Check if dictionary already exists
      final existing = await _repository.getDictionaryByName(dictName);
      if (existing != null) {
        skippedDicts.add(dictName);
        onDictionarySkipped?.call(dictName);
        continue;
      }

      final totalItems =
          rawEntries.length + rawPitchEntries.length + rawFreqEntries.length;
      onDictionaryStart?.call(dictName, totalItems, i, allDictNames.length);

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
            definitionTags: Value(raw['definitionTags'] ?? ''),
            rules: Value(raw['rules'] ?? ''),
            termTags: Value(raw['termTags'] ?? ''),
            glossaries: raw['glossaries']!,
            dictionaryId: dictionaryId,
          );
        }).toList();

        await _repository.batchInsertEntries(batch, batchSize: batch.length);
        inserted += batch.length;
        onProgress?.call(inserted, totalItems);
      }

      totalEntriesImported += inserted;

      // Insert pitch accents
      if (rawPitchEntries.isNotEmpty) {
        int pitchInserted = 0;
        for (var j = 0; j < rawPitchEntries.length; j += batchSize) {
          final end = (j + batchSize < rawPitchEntries.length)
              ? j + batchSize
              : rawPitchEntries.length;

          final batch = rawPitchEntries.sublist(j, end).map((raw) {
            return PitchAccentsCompanion.insert(
              expression: raw['expression'] as String,
              reading: Value(raw['reading'] as String? ?? ''),
              downstepPosition: raw['position'] as int,
              dictionaryId: dictionaryId,
            );
          }).toList();

          await _repository.batchInsertPitchAccents(
            batch,
            batchSize: batch.length,
          );
          pitchInserted += batch.length;
          onProgress?.call(inserted + pitchInserted, totalItems);
        }
        totalPitchAccentsImported += pitchInserted;
      }

      // Insert frequencies
      int totalFreqInserted = 0;
      if (rawFreqEntries.isNotEmpty) {
        int freqInserted = 0;
        for (var j = 0; j < rawFreqEntries.length; j += batchSize) {
          final end = (j + batchSize < rawFreqEntries.length)
              ? j + batchSize
              : rawFreqEntries.length;

          final batch = rawFreqEntries.sublist(j, end).map((raw) {
            return FrequenciesCompanion.insert(
              expression: raw['expression'] as String,
              reading: Value(raw['reading'] as String? ?? ''),
              frequencyRank: raw['rank'] as int,
              dictionaryId: dictionaryId,
            );
          }).toList();

          await _repository.batchInsertFrequencies(
            batch,
            batchSize: batch.length,
          );
          freqInserted += batch.length;
          onProgress?.call(
            inserted +
                (rawPitchEntries.isEmpty ? 0 : rawPitchEntries.length) +
                freqInserted,
            totalItems,
          );
        }
        totalFreqInserted += freqInserted;
      }

      importedDicts.add(dictName);
      totalFrequenciesImported += totalFreqInserted;
    }

    return CollectionImportResult(
      importedDictionaries: importedDicts,
      skippedDictionaries: skippedDicts,
      totalEntriesImported: totalEntriesImported,
      totalPitchAccentsImported: totalPitchAccentsImported,
      totalFrequenciesImported: totalFrequenciesImported,
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

      // Track termMeta rows array
      bool inTermMetaRows = false;
      int termMetaRowsDepth = 0;

      // Whole-row capture for termMeta rows.
      // Instead of tracking individual fields via SAX events, we capture
      // the entire row object as raw JSON and decode it afterwards.
      // This handles both flat format and Dexie $ wrapper format.
      bool inTermMetaRow = false;
      int metaRowCapNesting = 0;
      StringBuffer? metaRowCapBuf;
      final metaRowCapNeedsComma = <bool>[];
      bool metaRowCapClosedStructure = false;

      // Track individual term object
      bool inTermObject = false;
      int termObjectDepth = 0;
      String? currentKey;
      String? termExpression;
      String? termReading;
      String? termDictionary;
      String? termDefinitionTags;
      String? termRules;
      String? termTermTags;
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
      final pitchBatch = <Map<String, dynamic>>[];
      final freqBatch = <Map<String, dynamic>>[];
      const batchSize = 5000;

      await for (final event in eventStream) {
        switch (event.type) {
          case JsonEventType.beginObject:
            depth++;
            if (inTermMetaRow && metaRowCapNesting > 0) {
              // Inside a termMeta row capture — nested object
              if (metaRowCapNeedsComma.isNotEmpty &&
                  metaRowCapNeedsComma.last) {
                metaRowCapBuf?.write(',');
              }
              metaRowCapBuf?.write('{');
              metaRowCapNesting++;
              metaRowCapNeedsComma.add(false);
              metaRowCapClosedStructure = false;
            } else if (inTermMetaRows &&
                !inTermMetaRow &&
                depth == termMetaRowsDepth + 1) {
              // Starting a new termMeta row — begin whole-row capture
              inTermMetaRow = true;
              metaRowCapBuf = StringBuffer('{');
              metaRowCapNesting = 1;
              metaRowCapNeedsComma.clear();
              metaRowCapNeedsComma.add(false);
              metaRowCapClosedStructure = false;
            } else if (inGlossaryArray && capNesting > 0) {
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
              termDefinitionTags = null;
              termRules = null;
              termTermTags = null;
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
            if (inTermMetaRow && metaRowCapNesting > 0) {
              metaRowCapBuf?.write('}');
              metaRowCapNesting--;
              if (metaRowCapNeedsComma.isNotEmpty) {
                metaRowCapNeedsComma.removeLast();
              }
              if (metaRowCapNesting == 0) {
                // Finished capturing the entire termMeta row — decode and extract pitch/freq data
                _processTermMetaRow(
                  metaRowCapBuf.toString(),
                  pitchBatch,
                  freqBatch,
                );
                metaRowCapBuf = null;
                metaRowCapNeedsComma.clear();
                inTermMetaRow = false;

                if (pitchBatch.length >= batchSize) {
                  sendPort.send([
                    'pitch_batch',
                    List<Map<String, dynamic>>.of(pitchBatch),
                  ]);
                  pitchBatch.clear();
                }
                if (freqBatch.length >= batchSize) {
                  sendPort.send([
                    'freq_batch',
                    List<Map<String, dynamic>>.of(freqBatch),
                  ]);
                  freqBatch.clear();
                }
              } else {
                metaRowCapClosedStructure = true;
                if (metaRowCapNeedsComma.isNotEmpty) {
                  metaRowCapNeedsComma.last = true;
                }
              }
            } else if (inGlossaryArray && capNesting > 0) {
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
                  'definitionTags': termDefinitionTags ?? '',
                  'rules': termRules ?? '',
                  'termTags': termTermTags ?? '',
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
            if (inTermMetaRow && metaRowCapNesting > 0) {
              // Inside a termMeta row capture — nested array
              if (metaRowCapNeedsComma.isNotEmpty &&
                  metaRowCapNeedsComma.last) {
                metaRowCapBuf?.write(',');
              }
              metaRowCapBuf?.write('[');
              metaRowCapNesting++;
              metaRowCapNeedsComma.add(false);
              metaRowCapClosedStructure = false;
            } else if (inGlossaryArray && capNesting > 0) {
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
            } else if (inTableObject &&
                currentTableName == 'termMeta' &&
                pendingPropertyName == 'rows') {
              inTermMetaRows = true;
              termMetaRowsDepth = depth;
              pendingPropertyName = null;
            } else if (!inDataDataArray && pendingPropertyName == 'data') {
              // Heuristic: the inner "data" array (data.data)
              inDataDataArray = true;
              dataDataDepth = depth;
              pendingPropertyName = null;
            }

          case JsonEventType.endArray:
            if (inTermMetaRow && metaRowCapNesting > 0) {
              metaRowCapBuf?.write(']');
              metaRowCapNesting--;
              if (metaRowCapNeedsComma.isNotEmpty) {
                metaRowCapNeedsComma.removeLast();
              }
              if (metaRowCapNesting == 0) {
                // This shouldn't happen (rows are objects, not arrays)
                // but handle gracefully
                inTermMetaRow = false;
                metaRowCapBuf = null;
                metaRowCapNeedsComma.clear();
              } else {
                metaRowCapClosedStructure = true;
                if (metaRowCapNeedsComma.isNotEmpty) {
                  metaRowCapNeedsComma.last = true;
                }
              }
            } else if (inGlossaryArray && capNesting > 0) {
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
            } else if (inTermMetaRows && depth == termMetaRowsDepth) {
              inTermMetaRows = false;
            } else if (inTermsRows && depth == termsRowsDepth) {
              inTermsRows = false;
            } else if (inDataDataArray && depth == dataDataDepth) {
              inDataDataArray = false;
            }
            depth--;

          case JsonEventType.propertyName:
            if (inTermMetaRow && metaRowCapNesting > 0) {
              if (metaRowCapNeedsComma.isNotEmpty &&
                  metaRowCapNeedsComma.last) {
                metaRowCapBuf?.write(',');
              }
              metaRowCapBuf?.write('${jsonEncode(event.value)}:');
              if (metaRowCapNeedsComma.isNotEmpty) {
                metaRowCapNeedsComma.last = false;
              }
              metaRowCapClosedStructure = false;
            } else if (inGlossaryArray && capNesting > 0) {
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
            if (inTermMetaRow && metaRowCapNesting > 0) {
              if (!metaRowCapClosedStructure) {
                metaRowCapBuf?.write(jsonEncode(event.value));
              }
              metaRowCapClosedStructure = false;
              if (metaRowCapNeedsComma.isNotEmpty) {
                metaRowCapNeedsComma.last = true;
              }
            } else if (inGlossaryArray && capNesting > 0) {
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
                  break;
                case 'reading':
                  termReading = event.value?.toString();
                  break;
                case 'dictionary':
                  termDictionary = event.value?.toString();
                  break;
                case 'definitionTags':
                case 'definition_tags':
                  termDefinitionTags = _stringifyTagValue(event.value);
                  break;
                case 'rules':
                  termRules = _stringifyTagValue(event.value);
                  break;
                case 'termTags':
                case 'term_tags':
                  termTermTags = _stringifyTagValue(event.value);
                  break;
                case null:
                  break;
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
            if (inTermMetaRow && metaRowCapNesting > 0) {
              if (!metaRowCapClosedStructure) {
                if (metaRowCapNeedsComma.isNotEmpty &&
                    metaRowCapNeedsComma.last) {
                  metaRowCapBuf?.write(',');
                }
                metaRowCapBuf?.write(jsonEncode(event.value));
              }
              metaRowCapClosedStructure = false;
              if (metaRowCapNeedsComma.isNotEmpty) {
                metaRowCapNeedsComma.last = true;
              }
            } else if (inGlossaryArray && capNesting > 0) {
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

      // Send remaining batches
      if (batch.isNotEmpty) {
        sendPort.send(['batch', batch]);
      }
      if (pitchBatch.isNotEmpty) {
        sendPort.send(['pitch_batch', pitchBatch]);
      }
      if (freqBatch.isNotEmpty) {
        sendPort.send(['freq_batch', freqBatch]);
      }

      sendPort.send(['done']);
    } catch (e) {
      sendPort.send(['error', e.toString()]);
    }
  }

  /// Decode a captured termMeta row JSON and extract pitch accent and frequency data.
  ///
  /// Handles two formats:
  /// - Flat: `{"expression":"...","mode":"pitch","data":{...},"dictionary":"..."}`
  /// - Dexie $ wrapper: `{"$":[1,{"expression":"...","mode":"pitch",...}],"$types":{...}}`
  static void _processTermMetaRow(
    String rowJson,
    List<Map<String, dynamic>> pitchBatch, [
    List<Map<String, dynamic>>? freqBatch,
  ]) {
    try {
      final row = jsonDecode(rowJson) as Map<String, dynamic>;

      // Detect format: Dexie $ wrapper or flat
      Map<String, dynamic> inner;
      if (row.containsKey(r'$') && row[r'$'] is List) {
        // Dexie wrapper: actual data is at $[1]
        final dollarArray = row[r'$'] as List;
        if (dollarArray.length < 2 || dollarArray[1] is! Map) return;
        inner = dollarArray[1] as Map<String, dynamic>;
      } else if (row.containsKey('expression')) {
        // Flat format
        inner = row;
      } else {
        return;
      }

      final expression = inner['expression']?.toString();
      final mode = inner['mode']?.toString();
      final dictionary =
          inner['dictionary']?.toString() ?? 'Unknown Dictionary';
      if (expression == null || expression.isEmpty) return;

      if (mode == 'freq' && freqBatch != null) {
        final data = inner['data'];
        if (data == null) return;

        final parsed = _parseFrequencyData(data);
        final rank = parsed.rank;
        final reading = parsed.reading;

        if (rank != null) {
          freqBatch.add({
            'expression': expression,
            'reading': reading,
            'rank': rank,
            'dictionary': dictionary,
          });
        }
        return;
      }

      if (mode != 'pitch') return;

      final data = inner['data'];
      if (data == null) return;

      // data can be a single object or an array of objects
      final dataItems = <Map<String, dynamic>>[];
      if (data is Map<String, dynamic>) {
        dataItems.add(data);
      } else if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            dataItems.add(item);
          }
        }
      }

      for (final dataItem in dataItems) {
        final reading = dataItem['reading']?.toString() ?? '';
        final pitches = dataItem['pitches'];
        if (pitches is! List) continue;

        for (final p in pitches) {
          if (p is Map && p['position'] is int) {
            pitchBatch.add({
              'expression': expression,
              'reading': reading,
              'position': p['position'] as int,
              'dictionary': dictionary,
            });
          }
        }
      }
    } catch (_) {
      // Skip malformed rows
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
        final definitionTags = _stringifyTagValue(
          term.length > 2 ? term[2] : null,
        );
        final rules = _stringifyTagValue(term.length > 3 ? term[3] : null);
        final termTags = _stringifyTagValue(term.length > 7 ? term[7] : null);

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
            definitionTags: Value(definitionTags),
            rules: Value(rules),
            termTags: Value(termTags),
            glossaries: jsonEncode(glossaryList),
            dictionaryId: 0, // Placeholder — will be replaced after insert
          ),
        );
      }
    }

    // 2b. Parse all kanji_bank_*.json files (e.g. KANJIDIC)
    final kanjiBankFiles = archive.files
        .where(
          (f) => f.name.startsWith('kanji_bank_') && f.name.endsWith('.json'),
        )
        .toList();

    for (final kanjiBank in kanjiBankFiles) {
      final content = utf8.decode(kanjiBank.content as List<int>);
      final kanjiArray = jsonDecode(content) as List<dynamic>;

      for (final kanji in kanjiArray) {
        if (kanji is! List || kanji.length < 5) continue;

        final character = kanji[0]?.toString() ?? '';
        final onyomi = _stringifyKanjiReadingSource(kanji[1]);
        final kunyomi = _stringifyKanjiReadingSource(kanji[2]);
        // kanji[3] = tags (unused)
        final meanings = kanji[4];

        if (character.isEmpty) continue;

        final onyomiReadings = _normalizeKanjiReadings(kanji[1]);
        final kunyomiReadings = _normalizeKanjiReadings(kanji[2]);

        // Combine onyomi and kunyomi as reading
        final readingParts = <String>[
          if (onyomi.isNotEmpty) onyomi,
          if (kunyomi.isNotEmpty) kunyomi,
        ];
        final reading = readingParts.join(' ');

        // Build glossary from meanings array
        final glossaryList = <String>[];
        if (meanings is List) {
          for (final m in meanings) {
            if (m is String && m.isNotEmpty) glossaryList.add(m);
          }
        }

        entries.add(
          DictionaryEntriesCompanion.insert(
            expression: character,
            reading: Value(reading),
            entryKind: const Value(DictionaryEntryKinds.kanji),
            kanjiOnyomi: Value(encodeKanjiReadings(onyomiReadings)),
            kanjiKunyomi: Value(encodeKanjiReadings(kunyomiReadings)),
            glossaries: jsonEncode(glossaryList),
            dictionaryId: 0,
          ),
        );
      }
    }

    // 3. Parse all term_meta_bank_*.json files for pitch accents and frequencies
    final pitchAccents = <PitchAccentsCompanion>[];
    final frequencies = <FrequenciesCompanion>[];

    final metaBankFiles = archive.files
        .where(
          (f) =>
              f.name.startsWith('term_meta_bank_') && f.name.endsWith('.json'),
        )
        .toList();

    for (final metaBank in metaBankFiles) {
      final content = utf8.decode(metaBank.content as List<int>);
      final metaArray = jsonDecode(content) as List<dynamic>;

      for (final meta in metaArray) {
        if (meta is! List || meta.length < 3) continue;

        final expression = meta[0]?.toString() ?? '';
        final mode = meta[1]?.toString() ?? '';
        if (expression.isEmpty) continue;

        if (mode == 'pitch') {
          final data = meta[2];
          if (data is! Map) continue;

          final reading = data['reading']?.toString() ?? '';
          final pitches = data['pitches'];
          if (pitches is! List) continue;

          for (final pitch in pitches) {
            if (pitch is! Map) continue;
            final position = pitch['position'];
            if (position is! int) continue;

            pitchAccents.add(
              PitchAccentsCompanion.insert(
                expression: expression,
                reading: Value(reading),
                downstepPosition: position,
                dictionaryId: 0,
              ),
            );
          }
        } else if (mode == 'freq') {
          final data = meta[2];
          final parsed = _parseFrequencyData(data);
          final rank = parsed.rank;
          final reading = parsed.reading;

          if (rank != null) {
            frequencies.add(
              FrequenciesCompanion.insert(
                expression: expression,
                reading: Value(reading),
                frequencyRank: rank,
                dictionaryId: 0,
              ),
            );
          }
        }
      }
    }

    return YomitanParseResult(
      dictionaryName: dictionaryName,
      entries: entries,
      pitchAccents: pitchAccents,
      frequencies: frequencies,
    );
  }
}
