import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/services/firebase_runtime.dart';
import '../../data/models/mokuro_models.dart';
import '../../../settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import '../../../reader/data/services/mecab_service.dart';
import 'manga_ocr_client.dart';
import 'mokuro_word_segmenter.dart';
import 'ocr_auth_secret_storage.dart';
import 'ocr_billing_client.dart';

/// WorkManager task name for OCR processing.
const ocrTaskName = 'mekuru_ocr_processing';

/// Unique task tag prefix combined with bookId for cancellation.
const ocrTaskTagPrefix = 'ocr_';

/// SharedPreferences key prefix for OCR progress per book.
const ocrProgressKeyPrefix = 'ocr.progress.';

/// SharedPreferences key prefix for the active OCR billing job per book.
const ocrActiveJobKeyPrefix = 'ocr.job.';

/// SharedPreferences queue of billing finalizations that need to be retried.
const ocrPendingFinalizationsKey = 'ocr.pending_finalizations';

/// SharedPreferences key for the OCR server URL.
const ocrServerUrlKey = 'app.ocr_server_url';

/// Default OCR server URL (Modal deployment).
const defaultOcrServerUrl = ocr_server_config.defaultOcrServerUrl;

/// Save interval write partial results every N pages.
const _saveIntervalPages = 10;

/// Stop processing after this many consecutive page failures.
/// The OCR client already retries each page 3 times internally, so
/// consecutive failures at this level indicate a persistent problem.
const _maxConsecutiveFailures = 3;

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
  final String? errorMessage;

  const OcrProgress({
    required this.completed,
    required this.total,
    required this.status,
    this.avgSecondsPerPage,
    this.errorMessage,
  });

  String toJson() => json.encode({
    'completed': completed,
    'total': total,
    'status': status,
    if (avgSecondsPerPage != null) 'avgSecondsPerPage': avgSecondsPerPage,
    if (errorMessage != null) 'errorMessage': errorMessage,
  });

  factory OcrProgress.fromJson(String jsonStr) {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    return OcrProgress(
      completed: data['completed'] as int,
      total: data['total'] as int,
      status: data['status'] as String,
      avgSecondsPerPage: (data['avgSecondsPerPage'] as num?)?.toDouble(),
      errorMessage: data['errorMessage'] as String?,
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
            errorMessage: _describeOcrError(e),
          ),
        );
      } catch (progressError) {
        // Last-resort handler — can't even save failure state.
        debugPrint(
          '[OCR_WORKER] failed to save error progress: $progressError',
        );
      }
      return false;
    }
  });
}

/// Flush any queued OCR job finalizations that could not be sent earlier.
Future<void> flushPendingOcrFinalizations() async {
  final prefs = await SharedPreferences.getInstance();
  final pending = prefs.getStringList(ocrPendingFinalizationsKey) ?? const [];
  if (pending.isEmpty) return;

  final billingClient = OcrBillingClient();
  final remaining = <String>[];

  try {
    for (final entry in pending) {
      try {
        final payload = json.decode(entry) as Map<String, dynamic>;
        final jobId = payload['jobId'] as String?;
        final status = payload['status'] as String?;
        if (jobId == null || status == null) continue;
        await billingClient.finalizeOcrJob(jobId: jobId, status: status);
      } catch (_) {
        remaining.add(entry);
      }
    }
  } finally {
    billingClient.dispose();
  }

  if (remaining.isEmpty) {
    await prefs.remove(ocrPendingFinalizationsKey);
  } else {
    await prefs.setStringList(ocrPendingFinalizationsKey, remaining);
  }
}

/// The actual OCR processing logic run by WorkManager.
Future<bool> _processOcrTask(Map<String, dynamic> inputData) async {
  final bookId = inputData['bookId'] as int;
  final cacheFilePath = inputData['cacheFilePath'] as String;
  final imageDir = inputData['imageDir'] as String;
  final jobId = inputData['jobId'] as String?;

  final prefs = await SharedPreferences.getInstance();
  final serverUrl = ocr_server_config.normalizeOcrServerUrl(
    prefs.getString(ocrServerUrlKey) ?? defaultOcrServerUrl,
  );
  final usesBuiltInServer = ocr_server_config.isBuiltInOcrServerUrl(serverUrl);
  final authSecretStorage = OcrAuthSecretStorage();
  final customBearerKey = usesBuiltInServer
      ? null
      : await authSecretStorage.loadCustomServerBearerKey();
  final effectiveJobId = usesBuiltInServer ? jobId : null;

  await flushPendingOcrFinalizations();

  if (serverUrl.isEmpty) {
    await OcrProgress.save(
      prefs,
      bookId,
      const OcrProgress(
        completed: 0,
        total: 0,
        status: OcrStatus.failed,
        errorMessage: 'OCR server URL is not configured.',
      ),
    );
    await _clearActiveOcrJob(bookId);
    return false;
  }

  if (!usesBuiltInServer &&
      ocr_server_config.validateOcrServerUrl(serverUrl) != null) {
    await OcrProgress.save(
      prefs,
      bookId,
      const OcrProgress(
        completed: 0,
        total: 0,
        status: OcrStatus.failed,
        errorMessage:
            'OCR server URL is invalid. Use a full http:// or https:// URL.',
      ),
    );
    await _clearActiveOcrJob(bookId);
    return false;
  }

  if (!usesBuiltInServer && customBearerKey == null) {
    await OcrProgress.save(
      prefs,
      bookId,
      const OcrProgress(
        completed: 0,
        total: 0,
        status: OcrStatus.failed,
        errorMessage: 'No bearer key configured for custom OCR server.',
      ),
    );
    await _clearActiveOcrJob(bookId);
    return false;
  }

  String? builtInBearerToken;
  if (usesBuiltInServer) {
    final ocrUser = await FirebaseRuntime.instance.ensureOcrUser();
    builtInBearerToken = await ocrUser.getIdToken();
    if (builtInBearerToken == null || builtInBearerToken.isEmpty) {
      await OcrProgress.save(
        prefs,
        bookId,
        const OcrProgress(
          completed: 0,
          total: 0,
          status: OcrStatus.failed,
          errorMessage: 'Could not authenticate with OCR service.',
        ),
      );
      await _clearActiveOcrJob(bookId);
      return false;
    }
  }

  try {
    await MecabService.instance.init();
  } catch (e) {
    debugPrint(
      '[OCR_WORKER] MeCab init failed (word segmentation may be skipped): $e',
    );
  }

  final bearerToken = usesBuiltInServer
      ? builtInBearerToken!
      : customBearerKey!;
  final ocrClient = MangaOcrClient(
    serverUrl: serverUrl,
    getBearerToken: () => bearerToken,
  );
  final billingClient = effectiveJobId == null ? null : OcrBillingClient();
  var finalizationSent = false;

  Future<void> finalizeIfNeeded(String status) async {
    if (effectiveJobId == null || finalizationSent) {
      await _clearActiveOcrJob(bookId);
      return;
    }

    finalizationSent = true;
    try {
      await billingClient!.finalizeOcrJob(
        jobId: effectiveJobId,
        status: status,
      );
    } catch (_) {
      await _queuePendingOcrFinalization(effectiveJobId, status);
    } finally {
      await _clearActiveOcrJob(bookId);
    }
  }

  try {
    final cacheFile = File(cacheFilePath);
    if (!cacheFile.existsSync()) {
      await finalizeIfNeeded(OcrStatus.failed);
      return false;
    }

    final cacheJson =
        json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(cacheJson);

    final pagesToProcess = <int>[];
    for (var i = 0; i < mokuroBook.pages.length; i++) {
      if (mokuroBook.pages[i].blocks.isEmpty) {
        pagesToProcess.add(i);
      }
    }

    if (pagesToProcess.isEmpty) {
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
      await finalizeIfNeeded(OcrStatus.completed);
      return true;
    }

    final total = pagesToProcess.length;
    var completed = 0;
    final stopwatch = Stopwatch()..start();
    final updatedPages = List<MokuroPage>.from(mokuroBook.pages);
    var consecutiveFailures = 0;
    var anyPageSucceeded = false;

    Future<void> saveRunningProgress() async {
      final avgSeconds = completed > 0
          ? stopwatch.elapsedMilliseconds / 1000.0 / completed
          : null;

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
    }

    Future<bool> failWithError(String errorMessage) async {
      await OcrProgress.save(
        prefs,
        bookId,
        OcrProgress(
          completed: completed,
          total: total,
          status: OcrStatus.failed,
          errorMessage: errorMessage,
        ),
      );
      await _saveCache(cacheFile, mokuroBook, updatedPages);
      await finalizeIfNeeded(OcrStatus.failed);
      return false;
    }

    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(completed: 0, total: total, status: OcrStatus.running),
    );

    for (final pageIndex in pagesToProcess) {
      final currentProgress = OcrProgress.load(prefs, bookId);
      if (currentProgress?.status == OcrStatus.cancelled) {
        await _saveCache(cacheFile, mokuroBook, updatedPages);
        await finalizeIfNeeded(OcrStatus.cancelled);
        return true;
      }

      final page = mokuroBook.pages[pageIndex];
      final imagePath = '$imageDir/${page.imageFileName}';
      final imageFile = File(imagePath);

      if (!imageFile.existsSync()) {
        completed++;
        await saveRunningProgress();
        continue;
      }

      try {
        final imageBytes = await imageFile.readAsBytes();
        final result = await ocrClient.processPage(
          imageBytes,
          page.imageFileName,
          jobId: effectiveJobId,
          pageIndex: effectiveJobId == null ? null : pageIndex,
        );

        final ocrPage = page.copyWith(blocks: result.blocks);
        updatedPages[pageIndex] = await _segmentSinglePageForLookup(ocrPage);
        completed++;
        consecutiveFailures = 0;
        anyPageSucceeded = true;
        await saveRunningProgress();

        if (completed % _saveIntervalPages == 0) {
          await _saveCache(cacheFile, mokuroBook, updatedPages);
        }
      } on OcrServerException catch (e) {
        if (e.statusCode == 401) {
          return failWithError(
            'Authentication failed. '
            'Check your server bearer key.',
          );
        }
        consecutiveFailures++;
        if (!anyPageSucceeded ||
            consecutiveFailures >= _maxConsecutiveFailures) {
          return failWithError(_describeOcrError(e));
        }
        completed++;
        await saveRunningProgress();
      } catch (e) {
        consecutiveFailures++;
        if (!anyPageSucceeded ||
            consecutiveFailures >= _maxConsecutiveFailures) {
          return failWithError(_describeOcrError(e));
        }
        completed++;
        await saveRunningProgress();
      }
    }

    final pagesToSave = _needsWordSegmentation(updatedPages)
        ? await _segmentPagesForLookup(updatedPages)
        : updatedPages;

    await _saveCache(
      cacheFile,
      mokuroBook,
      pagesToSave,
      ocrSourceOverride: 'custom_ocr',
    );
    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(completed: total, total: total, status: OcrStatus.completed),
    );
    await finalizeIfNeeded(OcrStatus.completed);
    return true;
  } catch (_) {
    await finalizeIfNeeded(OcrStatus.failed);
    rethrow;
  } finally {
    ocrClient.dispose();
    billingClient?.dispose();
  }
}

/// Build a user-friendly error description from an OCR processing error.
String _describeOcrError(Object error) {
  if (error is OcrServerException) {
    final msg = error.message.toLowerCase();
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'Authentication failed. Check your server bearer key.';
    }
    if (error.statusCode == 422) {
      return 'Server rejected the request: ${error.message}';
    }
    if (error.statusCode >= 500) {
      return 'OCR server error (${error.statusCode}). '
          'The server may be down or misconfigured.';
    }
    if (error.statusCode == 0) {
      // Network-level errors from the client
      if (msg.contains('connection refused') ||
          msg.contains('connection reset') ||
          msg.contains('no route to host')) {
        return 'Could not connect to OCR server. '
            'Check the server URL and that the server is running.';
      }
      if (msg.contains('timed out')) {
        return 'OCR server is not responding (timed out).';
      }
      if (msg.contains('no address associated') ||
          msg.contains('name or service not known') ||
          msg.contains('getaddrinfo') ||
          msg.contains('failed host lookup')) {
        return 'Could not resolve OCR server address. '
            'Check the server URL.';
      }
      return 'Network error: ${error.message}';
    }
    return 'OCR server returned error ${error.statusCode}: ${error.message}';
  }
  final desc = error.toString().toLowerCase();
  if (desc.contains('formatexception') || desc.contains('type \'')) {
    return 'OCR server returned a malformed response. '
        'Make sure the server URL points to a compatible OCR server.';
  }
  return 'Unexpected error: $error';
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
  final segmentedPages = <MokuroPage>[];

  for (final page in pages) {
    if (!_pageNeedsWordSegmentation(page)) {
      segmentedPages.add(page);
      continue;
    }

    try {
      segmentedPages.add(await _segmentSinglePageForLookup(page));
    } catch (_) {
      segmentedPages.add(page);
    }
  }

  return segmentedPages;
}

Future<MokuroPage> _segmentSinglePageForLookup(MokuroPage page) async {
  final strippedPage = page.copyWith(
    blocks: page.blocks
        .map((block) => block.copyWith(words: const []))
        .toList(),
  );
  final segmented = await MokuroWordSegmenter.segmentAllPages([strippedPage]);
  return segmented.first;
}

bool _pageNeedsWordSegmentation(MokuroPage page) {
  for (final block in page.blocks) {
    if (block.lines.isNotEmpty && block.words.isEmpty) {
      return true;
    }
  }

  return false;
}

/// Write updated pages back to the cache file.
Future<void> _saveCache(
  File cacheFile,
  MokuroBook originalBook,
  List<MokuroPage> updatedPages, {
  String? ocrSourceOverride,
}) async {
  final updated = MokuroBook(
    title: originalBook.title,
    imageDirPath: originalBook.imageDirPath,
    safTreeUri: originalBook.safTreeUri,
    safImageDirRelativePath: originalBook.safImageDirRelativePath,
    autoCropVersion: originalBook.autoCropVersion,
    ocrSource: ocrSourceOverride ?? originalBook.ocrSource,
    pages: updatedPages,
  );
  await cacheFile.writeAsString(json.encode(updated.toJson()));
}

Future<void> _queuePendingOcrFinalization(String jobId, String status) async {
  final prefs = await SharedPreferences.getInstance();
  final queue = List<String>.from(
    prefs.getStringList(ocrPendingFinalizationsKey) ?? const <String>[],
  );
  queue.add(json.encode({'jobId': jobId, 'status': status}));
  await prefs.setStringList(ocrPendingFinalizationsKey, queue);
}

Future<void> _storeActiveOcrJob(int bookId, String jobId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('$ocrActiveJobKeyPrefix$bookId', jobId);
}

Future<void> _clearActiveOcrJob(int bookId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$ocrActiveJobKeyPrefix$bookId');
}

/// Schedule an OCR task for a book.
Future<void> scheduleOcrTask({
  required int bookId,
  required String cacheFilePath,
  required String imageDir,
  String? jobId,
  int? reservedPages,
}) async {
  if ((jobId == null) != (reservedPages == null)) {
    throw ArgumentError('jobId and reservedPages must be provided together.');
  }

  await Workmanager().registerOneOffTask(
    '$ocrTaskTagPrefix$bookId',
    ocrTaskName,
    inputData: {
      'bookId': bookId,
      'cacheFilePath': cacheFilePath,
      'imageDir': imageDir,
      ...?jobId == null ? null : {'jobId': jobId},
      ...?reservedPages == null ? null : {'reservedPages': reservedPages},
    },
    tag: '$ocrTaskTagPrefix$bookId',
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );

  if (jobId != null) {
    await _storeActiveOcrJob(bookId, jobId);
  } else {
    await _clearActiveOcrJob(bookId);
  }
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

  final activeJobId = prefs.getString('$ocrActiveJobKeyPrefix$bookId');
  if (activeJobId != null) {
    final billingClient = OcrBillingClient();
    try {
      await billingClient.finalizeOcrJob(
        jobId: activeJobId,
        status: OcrStatus.cancelled,
      );
    } catch (_) {
      await _queuePendingOcrFinalization(activeJobId, OcrStatus.cancelled);
    } finally {
      billingClient.dispose();
      await _clearActiveOcrJob(bookId);
    }
  }

  await Workmanager().cancelByTag('$ocrTaskTagPrefix$bookId');
}

/// Remove queued/running OCR work and clear persisted OCR progress state.
Future<void> clearOcrTaskState(int bookId) async {
  final prefs = await SharedPreferences.getInstance();
  await OcrProgress.clear(prefs, bookId);
  await _clearActiveOcrJob(bookId);
  await Workmanager().cancelByTag('$ocrTaskTagPrefix$bookId');
}
