import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/platform/android_saf_service.dart';
import '../../../../core/services/firebase_runtime.dart';
import '../../../../core/services/sentry_setup.dart';
import '../../../../core/services/usage_telemetry.dart';
import '../../../../core/utils/atomic_file.dart';
import '../../data/models/mokuro_models.dart';
import '../../../settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import '../../../reader/data/services/mecab_service.dart';
import 'manga_cache_store.dart';
import 'manga_ocr_client.dart';
import 'vision_page_ocr.dart';
import 'mokuro_segmentation_repair.dart';
import 'mokuro_word_segmenter.dart';
import 'ocr_billing_client.dart';
import 'ocr_page_selection.dart';

/// WorkManager task name for OCR processing.
const ocrTaskName = 'mekuru_ocr_processing';

/// Unique task tag prefix combined with bookId for cancellation.
const ocrTaskTagPrefix = 'ocr_';

/// SharedPreferences key prefix for OCR progress per book.
const ocrProgressKeyPrefix = 'ocr.progress.';

/// SharedPreferences key prefix for the active OCR billing job per book.
const ocrActiveJobKeyPrefix = 'ocr.job.';

/// SharedPreferences key prefix for requested OCR stop actions per book.
const ocrStopRequestKeyPrefix = 'ocr.stop.';

/// SharedPreferences queue of billing finalizations that need to be retried.
const ocrPendingFinalizationsKey = 'ocr.pending_finalizations';

/// SharedPreferences key for the OCR server URL.
const ocrServerUrlKey = 'app.ocr_server_url';

/// Default OCR server URL (Modal deployment).
const defaultOcrServerUrl = ocr_server_config.defaultOcrServerUrl;

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

abstract class OcrStopRequest {
  static const paused = 'paused';
  static const deleted = 'deleted';
}

enum OcrTaskExecutionMode { workmanager, foreground }

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

    // Own isolate, own Sentry hub; see sentry_setup.dart.
    await initSentryForBackgroundIsolate();
    try {
      return await _processOcrTask(inputData);
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
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
    } finally {
      // Flush batched logs before the isolate goes away, bounded so a dead
      // network never delays the task's result.
      try {
        await Sentry.close().timeout(const Duration(seconds: 3));
      } catch (_) {
        // Best effort only; the job's outcome is already persisted.
      }
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

/// Claims the per-book job lease for a remote run, or returns null when the
/// plugin is unavailable or nothing needs OCR.
Future<String?> _claimRemoteLease({
  required int bookId,
  required String cachePath,
  List<int>? selectedPages,
  required bool replace,
}) async {
  if (!LocalMangaOcr.available) return null;
  final book = await MangaCacheStore.read(cachePath);
  final targets =
      selectedPages ??
      selectOcrPages(
        book,
        policy: replace
            ? OcrExistingPolicy.replace
            : OcrExistingPolicy.missingOnly,
      );
  if (targets.isEmpty) return null;
  final lease = await LocalMangaOcr.channel
      .invokeMapMethod<String, dynamic>('claimRemote', {
        'bookId': bookId,
        'title': book.title,
        'cachePath': cachePath,
        'pages': targets,
        'replace': replace,
      });
  return lease!['id'] as String;
}

/// The actual OCR processing logic run by WorkManager.
Future<bool> _processOcrTask(Map<String, dynamic> inputData) async {
  final leaseId =
      inputData['leaseId'] as String? ??
      await _claimRemoteLease(
        bookId: inputData['bookId'] as int,
        cachePath: inputData['cacheFilePath'] as String,
        selectedPages: (inputData['selectedPages'] as List?)?.cast<int>(),
        replace: inputData['replace'] == true,
      );
  try {
    var selectedPages = (inputData['selectedPages'] as List?)?.cast<int>();
    if (LocalMangaOcr.available && leaseId != null) {
      final lease = await LocalMangaOcr.channel
          .invokeMapMethod<String, dynamic>('ensureRemoteLease', {
            'id': leaseId,
          });
      final done = lease!['outcomes'] as Map? ?? const {};
      selectedPages = (lease['pages'] as List)
          .cast<int>()
          .where((index) => done[index.toString()] != 'done')
          .toList();
    }
    return await _processRemoteOcrTask({
      ...inputData,
      'leaseId': leaseId,
      'selectedPages': selectedPages,
    });
  } finally {
    if (LocalMangaOcr.available && leaseId != null) {
      await LocalMangaOcr.channel.invokeMethod('releaseRemote', {
        'id': leaseId,
      });
    }
  }
}

Future<bool> _processRemoteOcrTask(Map<String, dynamic> inputData) async {
  final jobStopwatch = Stopwatch()..start();
  final bookId = inputData['bookId'] as int;
  final cacheFilePath = inputData['cacheFilePath'] as String;
  final imageDir = inputData['imageDir'] as String;
  final jobId = inputData['jobId'] as String?;

  final prefs = await SharedPreferences.getInstance();
  final initialStopRequest = await _loadOcrStopRequest(
    prefs,
    bookId,
    reload: true,
  );
  if (initialStopRequest != null) {
    if (initialStopRequest == OcrStopRequest.deleted) {
      await _saveIdleOcrProgress(prefs, bookId);
    }
    return true;
  }
  // iOS on-device OCR: the same page loop, with Apple Vision in place of a
  // server, so none of the server and sign-in setup below applies.
  final onDevice = inputData['onDevice'] == true;
  final serverUrl = ocr_server_config.normalizeOcrServerUrl(
    prefs.getString(ocrServerUrlKey) ?? defaultOcrServerUrl,
  );
  final usesBuiltInServer =
      !onDevice && ocr_server_config.isBuiltInOcrServerUrl(serverUrl);
  final customBearerKey = onDevice || usesBuiltInServer
      ? null
      : await ocr_server_config.ocrCustomServerSecretStore.load();
  final effectiveJobId = usesBuiltInServer ? jobId : null;

  await flushPendingOcrFinalizations();

  if (!onDevice && serverUrl.isEmpty) {
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

  if (!onDevice &&
      !usesBuiltInServer &&
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

  if (!onDevice && !usesBuiltInServer && customBearerKey == null) {
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

  // The OCR worker only needs word segmentation, which IPADIC provides.
  // Skip the heavy UniDic-lite upgrade so this background isolate never
  // loads the ~260 MB enhanced dictionary. This is the worker's one init
  // attempt: per-page segmentation checks isInitialized instead of retrying.
  final mecabReady = await MecabService.instance.ensureInitialized(
    upgradeToEnhanced: false,
  );
  if (!mecabReady) {
    debugPrint('[OCR_WORKER] MeCab init failed (word segmentation skipped)');
  }

  final bearerToken = usesBuiltInServer ? builtInBearerToken : customBearerKey;
  final ocrClient = onDevice
      ? null
      : MangaOcrClient(
          serverUrl: serverUrl,
          getBearerToken: () => bearerToken!,
        );
  final processPage = ocrClient?.processPage ?? recognizePageWithVision;
  final billingClient = effectiveJobId == null ? null : OcrBillingClient();
  var finalizationSent = false;

  Future<void> finalizeIfNeeded(String status) async {
    await prefs.reload();
    final activeJobId = prefs.getString('$ocrActiveJobKeyPrefix$bookId');
    if (effectiveJobId == null ||
        finalizationSent ||
        activeJobId != effectiveJobId) {
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
      logFailure('ocr.job', const FileSystemException('pages cache missing'));
      await finalizeIfNeeded(OcrStatus.failed);
      return false;
    }

    final cacheJson =
        json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(cacheJson);

    final pagesToProcess = <int>[];
    final selected = (inputData['selectedPages'] as List?)?.cast<int>();
    for (var i = 0; i < mokuroBook.pages.length; i++) {
      if ((selected == null || selected.contains(i)) &&
          (inputData['replace'] == true ||
              _pageNeedsOcr(mokuroBook, mokuroBook.pages[i]))) {
        pagesToProcess.add(i);
      }
    }

    final total = mokuroBook.pages.length;
    final startingCompleted = total - pagesToProcess.length;
    var completed = 0;
    final stopwatch = Stopwatch()..start();
    final updatedPages = List<MokuroPage>.from(mokuroBook.pages);
    var consecutiveFailures = 0;
    var anyPageSucceeded = false;

    Future<String?> loadStopRequest() =>
        _loadOcrStopRequest(prefs, bookId, reload: true);

    Future<bool> handleStopRequest({
      required String? stopRequest,
      required List<MokuroPage> pagesToKeep,
    }) async {
      if (stopRequest == null) {
        return false;
      }

      if (stopRequest == OcrStopRequest.deleted) {
        await _saveIdleOcrProgress(prefs, bookId);
      } else {
        await OcrProgress.save(
          prefs,
          bookId,
          OcrProgress(
            completed: startingCompleted + completed,
            total: total,
            status: OcrStatus.cancelled,
          ),
        );
        await _saveCache(cacheFile, mokuroBook, pagesToKeep);
      }

      await finalizeIfNeeded(OcrStatus.cancelled);
      return true;
    }

    if (pagesToProcess.isEmpty) {
      if (await handleStopRequest(
        stopRequest: await loadStopRequest(),
        pagesToKeep: mokuroBook.pages,
      )) {
        return true;
      }

      if (pagesNeedWordSegmentation(mokuroBook.pages)) {
        final segmentedPages = await _segmentPagesForLookup(mokuroBook.pages);
        if (await handleStopRequest(
          stopRequest: await loadStopRequest(),
          pagesToKeep: segmentedPages,
        )) {
          return true;
        }
        await _saveCache(
          cacheFile,
          mokuroBook,
          segmentedPages,
          ocrCompletedOverride: true,
        );
        if (await handleStopRequest(
          stopRequest: await loadStopRequest(),
          pagesToKeep: segmentedPages,
        )) {
          return true;
        }
      } else if (!mokuroBook.ocrCompleted) {
        await _saveCache(
          cacheFile,
          mokuroBook,
          mokuroBook.pages,
          ocrCompletedOverride: true,
        );
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
      logUsage(
        'ocr.job',
        attrs: {
          'result': 'ok',
          'duration_ms': jobStopwatch.elapsedMilliseconds,
          'pages': 0,
        },
      );
      return true;
    }

    Future<void> saveRunningProgress() async {
      final avgSeconds = completed > 0
          ? stopwatch.elapsedMilliseconds / 1000.0 / completed
          : null;

      await OcrProgress.save(
        prefs,
        bookId,
        OcrProgress(
          completed: startingCompleted + completed,
          total: total,
          status: OcrStatus.running,
          avgSecondsPerPage: avgSeconds,
        ),
      );
    }

    Future<bool> failWithError(String errorMessage, Object error) async {
      logFailure('ocr.job', error);
      await OcrProgress.save(
        prefs,
        bookId,
        OcrProgress(
          completed: startingCompleted + completed,
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
      OcrProgress(
        completed: startingCompleted,
        total: total,
        status: OcrStatus.running,
      ),
    );

    for (final pageIndex in pagesToProcess) {
      if (await handleStopRequest(
        stopRequest: await loadStopRequest(),
        pagesToKeep: updatedPages,
      )) {
        return true;
      }

      // A reader closed mid-scan turns the wakelock off; take it back.
      if (inputData['keepAwake'] == true) await WakelockPlus.enable();
      final page = mokuroBook.pages[pageIndex];
      final imageBytes = await _readOcrPageImageBytes(
        mokuroBook: mokuroBook,
        page: page,
        imageDir: imageDir,
      );
      if (await handleStopRequest(
        stopRequest: await loadStopRequest(),
        pagesToKeep: updatedPages,
      )) {
        return true;
      }
      if (imageBytes == null) {
        consecutiveFailures++;
        if (!anyPageSucceeded ||
            consecutiveFailures >= _maxConsecutiveFailures) {
          return await failWithError(
            _describeMissingPageImage(
              mokuroBook: mokuroBook,
              page: page,
              imageDir: imageDir,
            ),
            const FileSystemException('page image unreadable'),
          );
        }
        completed++;
        await saveRunningProgress();
        continue;
      }

      try {
        final result = await processPage(
          imageBytes,
          page.imageFileName,
          jobId: effectiveJobId,
          pageIndex: effectiveJobId == null ? null : pageIndex,
        );

        final ocrPage = page.copyWith(
          blocks: result.blocks,
          ocr: {
            'completed': true,
            'source': onDevice ? 'vision' : 'remote',
            'modelVersion': onDevice ? 'apple-vision' : 'remote',
            'revision': (page.ocr?['revision'] as int? ?? 0) + 1,
            if (inputData['leaseId'] != null) 'jobId': inputData['leaseId'],
          },
        );
        updatedPages[pageIndex] = await _segmentSinglePageForLookup(ocrPage);
        if (LocalMangaOcr.available && inputData['leaseId'] != null) {
          await LocalMangaOcr.channel.invokeMethod('commitRemote', {
            'id': inputData['leaseId'],
            'index': pageIndex,
            'blocks': updatedPages[pageIndex].blocks
                .map((b) => b.toJson())
                .toList(),
          });
        } else {
          await _saveCache(cacheFile, mokuroBook, updatedPages);
        }
        completed++;
        consecutiveFailures = 0;
        anyPageSucceeded = true;

        if (await handleStopRequest(
          stopRequest: await loadStopRequest(),
          pagesToKeep: updatedPages,
        )) {
          return true;
        }
        await saveRunningProgress();
      } on OcrServerException catch (e) {
        if (await handleStopRequest(
          stopRequest: await loadStopRequest(),
          pagesToKeep: updatedPages,
        )) {
          return true;
        }
        if (e.statusCode == 401) {
          return await failWithError(
            'Authentication failed. '
            'Check your server bearer key.',
            e,
          );
        }
        consecutiveFailures++;
        if (!anyPageSucceeded ||
            consecutiveFailures >= _maxConsecutiveFailures) {
          return await failWithError(_describeOcrError(e), e);
        }
        completed++;
        await saveRunningProgress();
      } catch (e) {
        if (await handleStopRequest(
          stopRequest: await loadStopRequest(),
          pagesToKeep: updatedPages,
        )) {
          return true;
        }
        consecutiveFailures++;
        if (!anyPageSucceeded ||
            consecutiveFailures >= _maxConsecutiveFailures) {
          return await failWithError(_describeOcrError(e), e);
        }
        completed++;
        await saveRunningProgress();
      }
    }

    final pagesToSave = pagesNeedWordSegmentation(updatedPages)
        ? await _segmentPagesForLookup(updatedPages)
        : updatedPages;

    if (await handleStopRequest(
      stopRequest: await loadStopRequest(),
      pagesToKeep: pagesToSave,
    )) {
      return true;
    }

    await _saveCache(
      cacheFile,
      mokuroBook,
      pagesToSave,
      ocrSourceOverride: onDevice ? 'on_device' : 'custom_ocr',
      ocrCompletedOverride: updatedPages.every(
        (page) => page.hasOcr(mokuroBook),
      ),
    );
    if (await handleStopRequest(
      stopRequest: await loadStopRequest(),
      pagesToKeep: pagesToSave,
    )) {
      return true;
    }
    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(completed: total, total: total, status: OcrStatus.completed),
    );
    await finalizeIfNeeded(OcrStatus.completed);
    logUsage(
      'ocr.job',
      attrs: {
        'result': 'ok',
        'duration_ms': jobStopwatch.elapsedMilliseconds,
        'pages': pagesToProcess.length,
      },
    );
    return true;
  } catch (e) {
    logFailure('ocr.job', e);
    await finalizeIfNeeded(OcrStatus.failed);
    rethrow;
  } finally {
    ocrClient?.dispose();
    billingClient?.dispose();
  }
}

/// Build a user-friendly error description from an OCR processing error.
String _describeOcrError(Object error) {
  if (error is OcrServerException) {
    final msg = error.message.toLowerCase();
    if (error.statusCode == 401) {
      return 'Authentication failed. Check your server bearer key.';
    }
    if (error.statusCode == 403) {
      // job_forbidden: the OCR job belongs to a different account.
      if (error.code == 'job_forbidden') {
        return 'This OCR job belongs to a different account. '
            'Start a new OCR run.';
      }
      return 'Authentication failed. Check your server bearer key.';
    }
    if (error.statusCode == 402) {
      return 'Not enough OCR credits. ${error.message}';
    }
    if (error.statusCode == 404) {
      return 'The OCR job was not found. Start a new OCR run.';
    }
    if (error.statusCode == 409) {
      // job_expired or job_not_active
      return 'The OCR job is no longer active. Start a new OCR run.';
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

bool _pageNeedsOcr(MokuroBook book, MokuroPage page) {
  return !page.hasOcr(book);
}

Future<List<MokuroPage>> _segmentPagesForLookup(List<MokuroPage> pages) async {
  final segmentedPages = <MokuroPage>[];

  for (final page in pages) {
    if (!pageNeedsWordSegmentation(page)) {
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
  // The worker attempts MeCab init once at startup; if that failed, return
  // the page unchanged instead of re-attempting (and re-failing) the full
  // init for every page. The reader's self-heal repairs missing words later.
  if (!MecabService.instance.isInitialized) return page;
  final segmented = await MokuroWordSegmenter.segmentAllPages([page]);
  return segmented.first;
}

/// Write updated pages back to the cache file.
Future<void> _saveCache(
  File cacheFile,
  MokuroBook originalBook,
  List<MokuroPage> updatedPages, {
  String? ocrSourceOverride,
  bool? ocrCompletedOverride,
}) async {
  final updated = originalBook.copyWith(
    ocrSource: ocrSourceOverride ?? originalBook.ocrSource,
    ocrCompleted: ocrCompletedOverride,
    pages: updatedPages,
  );
  // Atomic write: the WorkManager process can be killed mid-write, and a
  // truncated cache would corrupt already-completed OCR results.
  if (LocalMangaOcr.available) {
    await MangaCacheStore.merge(
      cacheFile,
      before: json.encode(originalBook.toJson()),
      after: json.encode(updated.toJson()),
    );
  } else {
    await writeStringAtomic(cacheFile, json.encode(updated.toJson()));
  }
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

Future<void> _setOcrStopRequest(int bookId, String stopRequest) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('$ocrStopRequestKeyPrefix$bookId', stopRequest);
}

Future<void> _clearOcrStopRequest(int bookId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$ocrStopRequestKeyPrefix$bookId');
}

@visibleForTesting
Future<String?> loadOcrStopRequest(int bookId) async {
  final prefs = await SharedPreferences.getInstance();
  return _loadOcrStopRequest(prefs, bookId, reload: true);
}

Future<String?> _loadOcrStopRequest(
  SharedPreferences prefs,
  int bookId, {
  bool reload = false,
}) async {
  if (reload) {
    await prefs.reload();
  }
  return prefs.getString('$ocrStopRequestKeyPrefix$bookId');
}

Future<void> _saveIdleOcrProgress(SharedPreferences prefs, int bookId) {
  return OcrProgress.save(
    prefs,
    bookId,
    const OcrProgress(completed: 0, total: 0, status: OcrStatus.idle),
  );
}

Future<void> _finalizeActiveOcrJobAsCancelled({
  required SharedPreferences prefs,
  required int bookId,
}) async {
  await prefs.reload();
  final activeJobId = prefs.getString('$ocrActiveJobKeyPrefix$bookId');
  if (activeJobId == null) {
    await _clearActiveOcrJob(bookId);
    return;
  }

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

@visibleForTesting
Future<OcrProgress> buildScheduledOcrProgress({
  required String cacheFilePath,
  int? reservedPages,
}) async {
  var completed = 0;
  var total = reservedPages ?? 0;
  final cacheFile = File(cacheFilePath);
  if (await cacheFile.exists()) {
    try {
      final cacheJson =
          json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final mokuroBook = MokuroBook.fromJson(cacheJson);
      final pendingPageCount = mokuroBook.pages
          .where((page) => _pageNeedsOcr(mokuroBook, page))
          .length;
      if (pendingPageCount > 0) {
        completed = mokuroBook.pages.length - pendingPageCount;
        total = mokuroBook.pages.length;
      } else if (pagesNeedWordSegmentation(mokuroBook.pages)) {
        final pagesNeedingSegmentation = mokuroBook.pages
            .where(pageNeedsWordSegmentation)
            .length;
        completed = mokuroBook.pages.length - pagesNeedingSegmentation;
        total = mokuroBook.pages.length;
      } else if (mokuroBook.pages.isNotEmpty) {
        completed = mokuroBook.pages.length;
        total = mokuroBook.pages.length;
      }
    } catch (_) {
      // Leave total at the reserved/fallback value if the cache is unreadable.
    }
  }

  return OcrProgress(
    completed: completed,
    total: total,
    status: OcrStatus.running,
  );
}

Future<void> _saveScheduledOcrProgress({
  required int bookId,
  required String cacheFilePath,
  int? reservedPages,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final progress = await buildScheduledOcrProgress(
    cacheFilePath: cacheFilePath,
    reservedPages: reservedPages,
  );
  await OcrProgress.save(prefs, bookId, progress);
}

@visibleForTesting
Future<OcrTaskExecutionMode> determineOcrTaskExecutionMode({
  required String cacheFilePath,
}) async {
  // An iOS background task gets seconds, not the minutes a volume needs, and
  // cannot reach the app's own channels; scans there run while the app is open.
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return OcrTaskExecutionMode.foreground;
  }
  final cacheFile = File(cacheFilePath);
  if (!await cacheFile.exists()) {
    return OcrTaskExecutionMode.workmanager;
  }

  try {
    final cacheJson =
        json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final safTreeUri = cacheJson['safTreeUri'] as String?;
    final safImageDirRelativePath =
        cacheJson['safImageDirRelativePath'] as String?;
    if ((safTreeUri?.isNotEmpty ?? false) &&
        (safImageDirRelativePath?.isNotEmpty ?? false)) {
      return OcrTaskExecutionMode.foreground;
    }
  } catch (_) {
    // Fall back to WorkManager if the cache cannot be parsed yet.
  }

  return OcrTaskExecutionMode.workmanager;
}

Future<Uint8List?> _readOcrPageImageBytes({
  required MokuroBook mokuroBook,
  required MokuroPage page,
  required String imageDir,
}) async {
  if (mokuroBook.safTreeUri != null &&
      mokuroBook.safImageDirRelativePath != null) {
    final relativePath = p.posix.join(
      mokuroBook.safImageDirRelativePath!,
      page.imageFileName,
    );
    return AndroidSafService.readBytesFromTreePath(
      mokuroBook.safTreeUri!,
      relativePath,
    );
  }

  final imageFile = File(p.join(imageDir, page.imageFileName));
  if (!imageFile.existsSync()) {
    return null;
  }
  return imageFile.readAsBytes();
}

String _describeMissingPageImage({
  required MokuroBook mokuroBook,
  required MokuroPage page,
  required String imageDir,
}) {
  if (mokuroBook.safTreeUri != null &&
      mokuroBook.safImageDirRelativePath != null) {
    final relativePath = p.posix.join(
      mokuroBook.safImageDirRelativePath!,
      page.imageFileName,
    );
    return 'Could not read manga image "$relativePath" from the selected '
        'folder access grant. Re-import the manga if folder access changed.';
  }

  final imagePath = p.join(imageDir, page.imageFileName);
  return 'Could not read manga image "$imagePath". '
      'Check that the manga image folder is still available.';
}

/// iOS scans run inside the app, so one that was `running` when the app last
/// died is not running any more. Marks it cancelled: the badge stops claiming
/// progress, and pressing Start again continues, because finished pages are
/// skipped. A no-op elsewhere (WorkManager re-runs its own tasks).
Future<void> resetInterruptedIosOcr() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  final prefs = await SharedPreferences.getInstance();
  for (final bookId in _runningOcrBookIds(prefs)) {
    final progress = OcrProgress.load(prefs, bookId)!;
    await OcrProgress.save(
      prefs,
      bookId,
      OcrProgress(
        completed: progress.completed,
        total: progress.total,
        status: OcrStatus.cancelled,
        avgSecondsPerPage: progress.avgSecondsPerPage,
      ),
    );
    await _clearActiveOcrJob(bookId);
  }
}

/// iOS applies a full restore inside the running app, so this process's page
/// loops must stop writing into the library first. Best effort: a loop sees
/// its stop request at the next page boundary.
Future<void> pauseRunningIosOcr() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  final prefs = await SharedPreferences.getInstance();
  for (final bookId in _runningOcrBookIds(prefs)) {
    await cancelOcrTask(bookId);
  }
}

List<int> _runningOcrBookIds(SharedPreferences prefs) => [
  for (final key in prefs.getKeys())
    if (key.startsWith(ocrProgressKeyPrefix))
      if (int.tryParse(key.substring(ocrProgressKeyPrefix.length))
          case final bookId?)
        if (OcrProgress.load(prefs, bookId)?.status == OcrStatus.running)
          bookId,
];

/// Schedule an OCR task for a book.
Future<void> scheduleOcrTask({
  required int bookId,
  required String cacheFilePath,
  required String imageDir,
  String? jobId,
  int? reservedPages,
  List<int>? selectedPages,
  bool replace = false,
  bool onDevice = false,
}) async {
  if ((jobId == null) != (reservedPages == null)) {
    throw ArgumentError('jobId and reservedPages must be provided together.');
  }

  await _clearOcrStopRequest(bookId);
  final leaseId = await _claimRemoteLease(
    bookId: bookId,
    cachePath: cacheFilePath,
    selectedPages: selectedPages,
    replace: replace,
  );

  try {
    final executionMode = await determineOcrTaskExecutionMode(
      cacheFilePath: cacheFilePath,
    );
    if (executionMode == OcrTaskExecutionMode.foreground) {
      debugPrint('[OCR_WORKER] Using foreground OCR bookId=$bookId');
      await _saveScheduledOcrProgress(
        bookId: bookId,
        cacheFilePath: cacheFilePath,
        reservedPages: reservedPages,
      );
      if (jobId != null) {
        await _storeActiveOcrJob(bookId, jobId);
      } else {
        await _clearActiveOcrJob(bookId);
      }

      // A sleeping iPhone suspends the app and the scan with it.
      final keepAwake = defaultTargetPlatform == TargetPlatform.iOS;
      unawaited(() async {
        try {
          if (keepAwake) await WakelockPlus.enable();
          await _processOcrTask({
            'bookId': bookId,
            'cacheFilePath': cacheFilePath,
            'imageDir': imageDir,
            'leaseId': ?leaseId,
            'selectedPages': ?selectedPages,
            'replace': replace,
            'onDevice': onDevice,
            'keepAwake': keepAwake,
            ...?jobId == null ? null : {'jobId': jobId},
            ...?reservedPages == null ? null : {'reservedPages': reservedPages},
          });
        } catch (error, stackTrace) {
          debugPrint('[OCR_WORKER] Foreground OCR failed: $error');
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'ocr_background_worker',
              context: ErrorDescription('while running in-process OCR'),
            ),
          );
        } finally {
          // ponytail: not reference-counted, so a reader opened during the
          // scan loses its keep-awake when the scan ends; it takes it back the
          // next time it opens.
          if (keepAwake) await WakelockPlus.disable();
        }
      }());
      return;
    }

    await Workmanager().registerOneOffTask(
      '$ocrTaskTagPrefix$bookId',
      ocrTaskName,
      inputData: {
        'bookId': bookId,
        'cacheFilePath': cacheFilePath,
        'imageDir': imageDir,
        'leaseId': ?leaseId,
        'selectedPages': ?(LocalMangaOcr.available ? null : selectedPages),
        'replace': replace,
        ...?jobId == null ? null : {'jobId': jobId},
        ...?reservedPages == null ? null : {'reservedPages': reservedPages},
      },
      tag: '$ocrTaskTagPrefix$bookId',
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    await _saveScheduledOcrProgress(
      bookId: bookId,
      cacheFilePath: cacheFilePath,
      reservedPages: reservedPages,
    );

    if (jobId != null) {
      await _storeActiveOcrJob(bookId, jobId);
    } else {
      await _clearActiveOcrJob(bookId);
    }
  } catch (_) {
    await _cancelWorkmanagerTask(bookId);
    if (LocalMangaOcr.available && leaseId != null) {
      await LocalMangaOcr.channel.invokeMethod('releaseRemote', {
        'id': leaseId,
      });
    }
    rethrow;
  }
}

/// Cancel an OCR task for a book.
Future<void> cancelOcrTask(int bookId) async {
  if (LocalMangaOcr.available) {
    await LocalMangaOcr.channel.invokeMethod('cancelBook', {
      'bookId': bookId,
      'backend': 'remote',
    });
  }
  final prefs = await SharedPreferences.getInstance();
  final existingProgress = OcrProgress.load(prefs, bookId);
  await _setOcrStopRequest(bookId, OcrStopRequest.paused);
  await OcrProgress.save(
    prefs,
    bookId,
    OcrProgress(
      completed: existingProgress?.completed ?? 0,
      total: existingProgress?.total ?? 0,
      status: OcrStatus.cancelled,
    ),
  );
  await _finalizeActiveOcrJobAsCancelled(prefs: prefs, bookId: bookId);
  await _cancelWorkmanagerTask(bookId);
}

/// iOS never hands a scan to WorkManager (see
/// [determineOcrTaskExecutionMode]), and `workmanager_apple` throws on
/// `cancelByTag`.
Future<void> _cancelWorkmanagerTask(int bookId) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) return;
  await Workmanager().cancelByTag('$ocrTaskTagPrefix$bookId');
}

/// Remove queued/running OCR work and hide persisted OCR progress state.
Future<void> clearOcrTaskState(int bookId) async {
  if (LocalMangaOcr.available) {
    await LocalMangaOcr.channel.invokeMethod('cancelBook', {'bookId': bookId});
  }
  final prefs = await SharedPreferences.getInstance();
  await _setOcrStopRequest(bookId, OcrStopRequest.deleted);
  await _saveIdleOcrProgress(prefs, bookId);
  await _finalizeActiveOcrJobAsCancelled(prefs: prefs, bookId: bookId);
  await _cancelWorkmanagerTask(bookId);
}
