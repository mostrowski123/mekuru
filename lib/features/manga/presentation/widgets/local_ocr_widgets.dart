import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/local_ocr_providers.dart';

String localOcrReason(BuildContext context, String? code) {
  final l = context.l10n;
  return switch (code) {
    null || '' => '',
    'interrupted' || 'stopped' => l.localOcrInterrupted,
    'low_memory' => l.localOcrLowMemory,
    'too_hot' => l.localOcrTooHot,
    'low_battery' => l.localOcrLowBattery,
    'charging_required' => l.localOcrChargingRequired,
    'background_timeout' ||
    'background_start_denied' => l.localOcrBackgroundLimit,
    'runtime_error' => l.localOcrRuntimeError,
    'model_corrupt' => l.localOcrModelCorrupt,
    'image_access_lost' ||
    'image_unreadable' ||
    'image_changed' => l.localOcrAccessLost,
    'insufficient_storage' || 'storage_error' => l.localOcrStorageFull,
    'book_busy' => l.localOcrBusy,
    'model_busy' || 'download_busy' => l.localOcrModelBusy,
    'model_missing' || 'model_version_missing' => l.localOcrDownloadRequired,
    'unsupported_device' => l.localOcrUnsupported,
    _ => l.localOcrError(details: code),
  };
}

String localOcrEta(BuildContext context, OcrJobProgress job) {
  final seconds = job.etaSeconds;
  if (seconds == null || seconds <= 0) return '';
  final l = context.l10n;
  if (seconds < 60) {
    return l.ocrEtaSecondsRemaining(seconds: seconds);
  }
  if (seconds < 3600) {
    return l.ocrEtaMinutesRemaining(minutes: (seconds / 60).ceil());
  }
  final minutes = (seconds / 60).ceil();
  return l.ocrEtaHoursMinutesRemaining(
    hours: minutes ~/ 60,
    minutes: minutes % 60,
  );
}

String localOcrPhase(BuildContext context, OcrJobProgress job) {
  final l = context.l10n;
  return switch (job.status == 'running' ? job.phase : job.status) {
    'queued' => l.localOcrQueued,
    'preparing' => l.localOcrPreparing,
    'detecting' => l.localOcrDetecting,
    'recognizing' || 'running' => l.localOcrRecognizing,
    'pausing' => l.localOcrPausing,
    'cancelling' => l.localOcrCancelling,
    'paused' => l.localOcrPaused,
    'cancelled' => l.localOcrCancelled,
    'completed' => l.localOcrCompleted,
    'completedWithErrors' => l.localOcrCompletedErrors,
    'failed' => l.localOcrFailed,
    _ => job.status,
  };
}

Future<void> runLocalOcrAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localOcrReason(
              context,
              error is PlatformException ? error.code : '$error',
            ),
          ),
        ),
      );
    }
  }
}

/// Minutes a [pages]-page volume takes at the measured speed.
int localOcrVolumeMinutes(int loadMs, int pageMs, {int pages = 200}) =>
    ((loadMs + pages * pageMs) / 60000).ceil();

/// "Test device speed": times the real pipeline on the bundled sample page
/// and keeps the last result under the button.
class LocalOcrSpeedTestRow extends StatefulWidget {
  const LocalOcrSpeedTestRow({super.key});
  @override
  State<LocalOcrSpeedTestRow> createState() => _LocalOcrSpeedTestRowState();
}

class _LocalOcrSpeedTestRowState extends State<LocalOcrSpeedTestRow> {
  static const _pageKey = 'ocr.speed_test_page_ms';
  static const _loadKey = 'ocr.speed_test_load_ms';
  int? _pageMs;
  int? _loadMs;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageMs = prefs.getInt(_pageKey);
      final loadMs = prefs.getInt(_loadKey);
      if (!mounted || pageMs == null || loadMs == null) return;
      setState(() {
        _pageMs = pageMs;
        _loadMs = loadMs;
      });
    } catch (_) {
      // Without a preferences store only the remembered result is lost.
    }
  }

  Future<void> _run() async {
    final l = context.l10n;
    setState(() => _running = true);
    // Modal: native refuses scans, downloads and removal during the test, so
    // the UI should not offer them either.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(l.localOcrSpeedTestRunning),
            content: const LinearProgressIndicator(),
            actions: [
              TextButton(
                onPressed: () =>
                    runLocalOcrAction(ctx, LocalMangaOcr.benchmarkCancel),
                child: Text(l.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
    var cancelled = false;
    await runLocalOcrAction(context, () async {
      final Map<String, dynamic> result;
      try {
        result = await LocalMangaOcr.benchmark();
      } on PlatformException catch (error) {
        if (error.code != 'stopped') rethrow;
        cancelled = true;
        return;
      }
      final pageMs = (result['pageMs'] as num).toInt();
      final loadMs = (result['loadMs'] as num).toInt();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pageKey, pageMs);
      await prefs.setInt(_loadKey, loadMs);
      logUsage(
        'ocr.speed_test',
        attrs: {
          'page_ms': pageMs,
          'load_ms': loadMs,
          'blocks': (result['blocks'] as num?)?.toInt() ?? 0,
          'threads': (result['threads'] as num?)?.toInt() ?? 0,
        },
      );
      if (!mounted) return;
      setState(() {
        _pageMs = pageMs;
        _loadMs = loadMs;
      });
    });
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (cancelled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.localOcrSpeedTestCancelled)));
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pageMs = _pageMs;
    final loadMs = _loadMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.speed),
          label: Text(l.localOcrSpeedTest),
        ),
        if (pageMs != null && loadMs != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.localOcrSpeedTestResult(
                pageSeconds: (pageMs / 1000).toStringAsFixed(1),
                minutes: localOcrVolumeMinutes(loadMs, pageMs),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class LocalOcrJobCard extends StatelessWidget {
  final OcrJobProgress job;

  /// Called once the journal delete has landed, so the host can refresh rather
  /// than leave the card up until the next one-second poll.
  final VoidCallback? onDismissed;
  const LocalOcrJobCard({super.key, required this.job, this.onDismissed});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.localOcrOnDevice,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(localOcrPhase(context, job)),
            if (job.etaSeconds != null && job.etaSeconds! > 0)
              Text(localOcrEta(context, job)),
            Text(
              l.localOcrProgress(processed: job.processed, total: job.total),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: job.fraction),
            const SizedBox(height: 8),
            Text(
              l.localOcrOutcomeCounts(
                succeeded: job.succeeded,
                skipped: job.skipped,
                failed: job.failed,
              ),
            ),
            if (job.reason != null) Text(localOcrReason(context, job.reason)),
            Wrap(
              spacing: 8,
              children: [
                if (job.isActive &&
                    !const {'pausing', 'cancelling'}.contains(job.status))
                  TextButton(
                    onPressed: () => runLocalOcrAction(
                      context,
                      () => LocalMangaOcr.pause(job.id),
                    ),
                    child: Text(l.localOcrPause),
                  ),
                if (job.canResume)
                  TextButton(
                    onPressed: () => runLocalOcrAction(
                      context,
                      () => LocalMangaOcr.resume(
                        job.id,
                        retryFailed: job.failed > 0,
                      ),
                    ),
                    child: Text(
                      job.failed > 0 ? l.localOcrRetryFailed : l.localOcrResume,
                    ),
                  ),
                if (job.isActive || job.canResume)
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l.localOcrCancelJob),
                          content: Text(l.localOcrCancelDescription),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l.commonClose),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l.localOcrCancelJob),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await runLocalOcrAction(
                          context,
                          () => LocalMangaOcr.cancel(job.id),
                        );
                      }
                    },
                    child: Text(l.localOcrCancelJob),
                  ),
                if (!job.isActive)
                  TextButton(
                    onPressed: () => runLocalOcrAction(context, () async {
                      await LocalMangaOcr.dismiss(job.id);
                      onDismissed?.call();
                    }),
                    child: Text(l.localOcrDismiss),
                  ),
              ],
            ),
            if (job.failed > 0)
              ExpansionTile(
                title: Text(l.localOcrPageErrors),
                children: [
                  for (final entry
                      in (job.json['errors'] as Map? ?? {}).entries)
                    ListTile(
                      title: Text(
                        l.localOcrPageError(
                          page: int.parse(entry.key as String) + 1,
                          details: localOcrReason(
                            context,
                            entry.value as String,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Uses the same tile, tonal action and inline progress as other downloads.
class LocalOcrDownloadTile extends ConsumerStatefulWidget {
  const LocalOcrDownloadTile({super.key});
  @override
  ConsumerState<LocalOcrDownloadTile> createState() =>
      _LocalOcrDownloadTileState();
}

class _LocalOcrDownloadTileState extends ConsumerState<LocalOcrDownloadTile> {
  bool _acting = false;
  String _bytes(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _acting = true);
    await runLocalOcrAction(context, action);
    if (!mounted) return;
    setState(() => _acting = false);
    ref.invalidate(localOcrModelProvider);
  }

  Future<void> _download(OcrModelState model) => _act(() async {
    final wifi = await LocalMangaOcr.isWifiConnected();
    if (!mounted) return;
    if (!wifi) {
      final l = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.localOcrMobileDownloadTitle),
          content: Text(
            l.localOcrMobileDownloadBody(size: _bytes(model.totalBytes)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDownload),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await LocalMangaOcr.download(allowMetered: !wifi);
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(localOcrModelProvider);
    final model = state.asData?.value;
    final busy = _acting || model?.busy == true;
    final subtitle = model == null
        ? l.localOcrModelDescription
        : !model.supported
        ? l.localOcrUnsupported
        : model.installed
        ? l.localOcrModelReady
        : '${l.localOcrModelDescription} (${_bytes(model.totalBytes)})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            Icons.document_scanner_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l.localOcrModelTitle),
          subtitle: Text(subtitle),
          trailing: state.isLoading || _acting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : model?.supported != true
              ? null
              : model!.busy
              ? IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.close),
                  onPressed: () => _act(LocalMangaOcr.cancelDownload),
                )
              : model.installed
              ? IconButton(
                  tooltip: l.commonRemove,
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _act(LocalMangaOcr.removeModels),
                )
              : FilledButton.tonal(
                  onPressed: () => _download(model),
                  child: Text(
                    model.downloadedBytes > 0
                        ? l.localOcrResume
                        : l.commonDownload,
                  ),
                ),
        ),
        if (model?.busy == true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: model!.status == 'verifying' || model.totalBytes == 0
                      ? null
                      : (model.downloadedBytes / model.totalBytes).clamp(0, 1),
                ),
                const SizedBox(height: 4),
                Text(
                  switch (model.status) {
                    'queued' =>
                      model.error == 'wifi_required'
                          ? l.localOcrWaitingWifi
                          : l.localOcrDownloadQueued,
                    'verifying' => l.localOcrModelVerifying,
                    _ => l.localOcrDownloadSize(
                      done: _bytes(model.downloadedBytes),
                      total: _bytes(model.totalBytes),
                    ),
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        if (state.hasError ||
            (model?.error != null && model!.error != 'wifi_required'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              localOcrReason(
                context,
                state.hasError ? state.error.toString() : model!.error,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (model != null &&
            !model.installed &&
            !busy &&
            model.downloadedBytes > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.localOcrDownloadSize(
                      done: _bytes(model.downloadedBytes),
                      total: _bytes(model.totalBytes),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _act(LocalMangaOcr.removeModels),
                  child: Text(l.commonRemove),
                ),
              ],
            ),
          ),
        if (model?.installed == true)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LocalOcrSpeedTestRow(),
          ),
      ],
    );
  }
}
