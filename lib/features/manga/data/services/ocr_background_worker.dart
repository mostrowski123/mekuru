import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../firebase_options.dart';
import '../../data/models/mokuro_models.dart';
import '../../../reader/data/services/mecab_service.dart';
import 'manga_ocr_client.dart';
import 'mokuro_word_segmenter.dart';

/// WorkManager task name for OCR processing.
const ocrTaskName = 'mekuru_ocr_processing';

/// Unique task tag prefix — combined with bookId for cancellation.
const ocrTaskTagPrefix = 'ocr_';

/// SharedPreferences key prefix for OCR progress per book.
const ocrProgressKeyPrefix = 'ocr.progress.';

/// SharedPreferences key for the OCR server URL.
const ocrServerUrlKey = 'app.ocr_server_url';

/// Default OCR server URL (Modal deployment).
const defaultOcrServerUrl = 'https://mekuru-ocr.modal.run';

/// Save interval — write partial results every N pages.
const _saveIntervalPages = 10;

/// OCR processing status values.
abstract class OcrStatus {
  static const running = 'running';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const failed = 'failed';
  static const idle = 'idle';
}

/// Progress data stored in SharedPreferences as JSON.
class OcrProgress {
  final int completed;
  final int total;
  final String status;
  final double? avgSecondsPerPage;

  const OcrProgress({
    required this.completed,
    required this.total,
    required this.status,
    this.avgSecondsPerPage,
  });

  String toJson() => json.encode({
        'completed': completed,
        'total': total,
        'status': status,
        if (avgSecondsPerPage != null) 'avgSecondsPerPage': avgSecondsPerPage,
      });

  factory OcrProgress.fromJson(String jsonStr) {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    return OcrProgress(
      completed: data['completed'] as int,
      total: data['total'] as int,
      status: data['status'] as String,
      avgSecondsPerPage: (data['avgSecondsPerPage'] as num?)?.toDouble(),
    );
  }

  static OcrProgress? load(SharedPreferences prefs, int bookId) {
    final value = prefs.getString('$ocrProgressKeyPrefix$bookId');
    if (value == null) return null;
    try {
      return OcrProgress.fromJson(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    SharedPreferences prefs,
    int bookId,
    OcrProgress progress,
  ) async {
    await prefs.setString('$ocrProgressKeyPrefix$bookId', progress.toJson());
  }

  static Future<void> clear(SharedPreferences prefs, int bookId) async {
    await prefs.remove('$ocrProgressKeyPrefix$bookId');
  }
}

/// Top-level callback dispatcher for WorkManager.
/// Must be a top-level function (not a method or closure).
@pragma('vm:entry-point')
void ocrWorkerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != ocrTaskName || inputData == null) return true;

    try {
      return await _processOcrTask(inputData);
    } catch (e) {
      // Mark as failed so the UI can show an error
      try {
        final prefs = await SharedPreferences.getInstance();
        final bookId = inputData['bookId'] as int;
        await OcrProgress.save(
          prefs,
          bookId,
          OcrProgress(
            completed: 0,
            total: 0,
            status: OcrStatus.failed,
          ),
        );
      } catch (_) {}
      return false; // WorkManager will retry with backoff
    }
  });
}

/// The actual OCR processing logic run by WorkManager.
Future<bool> _processOcrTask(Map<String, dynamic> inputData) async {
  final bookId = inputData['bookId'] as int;
  final cacheFilePath = inputData['cacheFilePath'] as String;
  final imageDir = inputData['imageDir'] as String;

  // Initialize Firebase in the background isolate
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Get auth token
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  final prefs = await SharedPreferences.getInstance();

  // Best effort: initialize MeCab so final word segmentation matches
  // manual "Reprocess words". If it fails, segmentation falls back
  // to line-level tokens.
  try {
    await MecabService.instance.init();
  } catch (_) {}

  // Load OCR server URL from settings
  final serverUrl =
      prefs.getString(ocrServerUrlKey) ?? defaultOcrServerUrl;

  // Create OCR client
  final client = MangaOcrClient(
    serverUrl: serverUrl,
    getAuthToken: () {
      final currentUser = FirebaseAuth.instance.currentUser;
      // getIdToken is async but we need sync here — use cached token.
      // WorkManager tasks should refresh token at the start.
      return currentUser?.uid ?? '';
    },
  );

  try {
    // Read the pages cache file
    final cacheFile = File(cacheFilePath);
    if (!cacheFile.existsSync()) return false;

    final cacheJson =
        json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(cacheJson);

    // Find pages that need OCR (empty blocks)
    final pagesToProcess = <int>[];
    for (var i = 0; i < mokuroBook.pages.length; i++) {
      if (mokuroBook.pages[i].blocks.isEmpty) {
        pagesToProcess.add(i);
      }
    }

    if (pagesToProcess.isEmpty) {
      // Some legacy/partial imports can have OCR blocks but no word
      // segmentation yet. Ensure tap targets are available.
      if (_needsWordSegmentation(mokuroBook.pages)) {
        final segmentedPages = await _segmentPagesForLookup(mokuroBook.pages);
        await _saveCache(cacheFile, mokuroBook, segmentedPages);
      }
      await OcrProgress.save(
        prefs,
        bookId,
        OcrProgress(
          completed: mokuroBook.pages.length,
          total: mokuroBook.pages.length,
          status: OcrStatus.completed,
        ),
      );
      return true;
    }

    final total = pagesToProcess.length;
    var completed = 0;
    final stopwatch = Stopwatch()..start();
    final updatedPages = List<MokuroPage>.from(mokuroBook.pages);

    // Save initial progress
    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(completed: 0, total: total, status: OcrStatus.running),
    );

    // Get a fresh Firebase ID token for the auth header
    final idToken =
        await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';

    // Override client to use the actual token
    final authedClient = MangaOcrClient(
      serverUrl: serverUrl,
      getAuthToken: () => idToken,
    );

    for (final pageIndex in pagesToProcess) {
      // Check if cancelled
      final currentProgress = OcrProgress.load(prefs, bookId);
      if (currentProgress?.status == OcrStatus.cancelled) {
        // Save partial results and exit
        await _saveCache(cacheFile, mokuroBook, updatedPages);
        return true;
      }

      final page = mokuroBook.pages[pageIndex];
      final imagePath = '$imageDir/${page.imageFileName}';
      final imageFile = File(imagePath);

      if (!imageFile.existsSync()) {
        completed++;
        continue;
      }

      try {
        final imageBytes = await imageFile.readAsBytes();
        final result = await authedClient.processPage(
          imageBytes,
          page.imageFileName,
        );

        // Update the page with OCR blocks
        updatedPages[pageIndex] = page.copyWith(blocks: result.blocks);
        completed++;

        // Calculate average time per page
        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        final avgSeconds = elapsed / completed;

        // Update progress
        await OcrProgress.save(
          prefs,
          bookId,
          OcrProgress(
            completed: completed,
            total: total,
            status: OcrStatus.running,
            avgSecondsPerPage: avgSeconds,
          ),
        );

        // Periodically save partial results
        if (completed % _saveIntervalPages == 0) {
          await _saveCache(cacheFile, mokuroBook, updatedPages);
        }
      } on OcrServerException catch (e) {
        if (e.statusCode == 401) {
          // Auth failure — can't continue
          await OcrProgress.save(
            prefs,
            bookId,
            OcrProgress(
              completed: completed,
              total: total,
              status: OcrStatus.failed,
            ),
          );
          await _saveCache(cacheFile, mokuroBook, updatedPages);
          return false;
        }
        // Skip this page for other errors, continue processing
        completed++;
      }
    }

    // Final step before completion: compute word-level boxes for tap targets.
    final segmentedPages = await _segmentPagesForLookup(updatedPages);

    // Save final results (with words)
    await _saveCache(cacheFile, mokuroBook, segmentedPages);

    // Mark as completed
    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(
        completed: total,
        total: total,
        status: OcrStatus.completed,
      ),
    );

    authedClient.dispose();
    return true;
  } finally {
    client.dispose();
  }
}

bool _needsWordSegmentation(List<MokuroPage> pages) {
  for (final page in pages) {
    for (final block in page.blocks) {
      if (block.lines.isNotEmpty && block.words.isEmpty) {
        return true;
      }
    }
  }
  return false;
}

Future<List<MokuroPage>> _segmentPagesForLookup(List<MokuroPage> pages) async {
  // Rebuild words from OCR lines to keep lookup data consistent.
  final strippedPages = pages
      .map(
        (page) => page.copyWith(
          blocks: page.blocks
              .map((block) => block.copyWith(words: const []))
              .toList(),
        ),
      )
      .toList();
  return MokuroWordSegmenter.segmentAllPages(strippedPages);
}

/// Write updated pages back to the cache file.
Future<void> _saveCache(
  File cacheFile,
  MokuroBook originalBook,
  List<MokuroPage> updatedPages,
) async {
  final updated = MokuroBook(
    title: originalBook.title,
    imageDirPath: originalBook.imageDirPath,
    safTreeUri: originalBook.safTreeUri,
    safImageDirRelativePath: originalBook.safImageDirRelativePath,
    pages: updatedPages,
  );
  await cacheFile.writeAsString(json.encode(updated.toJson()));
}

/// Schedule an OCR task for a book.
Future<void> scheduleOcrTask({
  required int bookId,
  required String cacheFilePath,
  required String imageDir,
}) async {
  await Workmanager().registerOneOffTask(
    '$ocrTaskTagPrefix$bookId',
    ocrTaskName,
    inputData: {
      'bookId': bookId,
      'cacheFilePath': cacheFilePath,
      'imageDir': imageDir,
    },
    tag: '$ocrTaskTagPrefix$bookId',
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    backoffPolicy: BackoffPolicy.exponential,
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Cancel an OCR task for a book.
Future<void> cancelOcrTask(int bookId) async {
  final prefs = await SharedPreferences.getInstance();
  await OcrProgress.save(
    prefs,
    bookId,
    OcrProgress(
      completed: OcrProgress.load(prefs, bookId)?.completed ?? 0,
      total: OcrProgress.load(prefs, bookId)?.total ?? 0,
      status: OcrStatus.cancelled,
    ),
  );
  await Workmanager().cancelByTag('$ocrTaskTagPrefix$bookId');
}
