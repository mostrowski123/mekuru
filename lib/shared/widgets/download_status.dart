import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/utils/storage_full.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart'
    show ModelVerificationException;
import 'package:mekuru/features/manga/data/services/model_download_job.dart'
    show JobWait;
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:url_launcher/url_launcher.dart';

// Rows shown under a download tile: progress, an error, an attribution.

/// [DictionaryDownloadService] progress: how much of the zip has arrived,
/// then the import. Its silent finish gets a moving bar, so it does not
/// look stuck.
class DictionaryDownloadProgress extends StatelessWidget {
  const DictionaryDownloadProgress({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const share = DictionaryDownloadService.downloadShare;
    final finishing = progress >= DictionaryDownloadService.finishingProgress;
    return DownloadProgress(
      progress: finishing ? null : progress,
      label: switch (progress) {
        < share => l10n.downloadsDownloadingPercent(
          percent: (progress / share * 100).toInt(),
        ),
        _ when finishing => l10n.dictionaryImportFinishing,
        _ => l10n.downloadsImporting,
      },
    );
  }
}

class DownloadProgress extends StatelessWidget {
  const DownloadProgress({
    super.key,
    required this.progress,
    required this.label,
  });

  /// Null while there is no telling how far along it is.
  final double? progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class DownloadErrorText extends StatelessWidget {
  const DownloadErrorText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Live regions here and below: screen readers announce download results.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class DownloadSuccessText extends StatelessWidget {
  const DownloadSuccessText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.success,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class DownloadAttributionText extends StatelessWidget {
  const DownloadAttributionText({
    super.key,
    this.prefix = '',
    required this.linkText,
    required this.url,
    this.suffix = '',
  });

  final String prefix;
  final String linkText;
  final String url;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    // Text.rich, not RichText: it follows the system font size.
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          TextSpan(
            text: linkText,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
          ),
          if (suffix.isNotEmpty) TextSpan(text: suffix),
        ],
      ),
    );
  }
}

/// What a download tile's last download or delete came to: [downloaded] or
/// [deleted] when it worked (by default "Download complete." and
/// "Deleted."), else why it failed.
class DownloadOutcomeText extends StatelessWidget {
  const DownloadOutcomeText(
    this.outcome, {
    super.key,
    this.downloaded,
    this.deleted,
  });

  final TileOutcome outcome;
  final String? downloaded;
  final String? deleted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (outcome) {
      (action: TileAction.download, error: null) => DownloadSuccessText(
        text: downloaded ?? l10n.downloadsDownloadComplete,
      ),
      (action: TileAction.delete, error: null) => DownloadSuccessText(
        text: deleted ?? l10n.downloadsDeleted,
      ),
      (action: TileAction.download, :final error?) => DownloadErrorText(
        text: dictionaryDownloadError(l10n, error)!,
      ),
      (action: TileAction.delete, error: _?) => DownloadErrorText(
        text: l10n.downloadsDeleteFailed,
      ),
    };
  }
}

/// What a background download job's row says in place of a percentage that
/// stands still; null when nothing holds it up.
String? jobWaitText(AppLocalizations l10n, JobWait wait) => switch (wait) {
  JobWait.none => null,
  JobWait.wifi => l10n.localOcrWaitingWifi,
  JobWait.connection => l10n.downloadWaitingConnection,
  JobWait.retry => l10n.downloadRetrying,
};

/// The High quality translation model's download row: why it waits
/// ([jobWaitText]), else the [percent] it has reached.
String highQualityDownloadText(
  AppLocalizations l10n, {
  required int percent,
  required JobWait wait,
}) =>
    jobWaitText(l10n, wait) ??
    l10n.translationHighQualityDownloading(percent: '$percent');

/// Why a download (dictionary, translation or OCR model) failed, worded for
/// the user; null when it did not. Every way one ends has its own words, and
/// anything else says only that it didn't finish: an exception's own text
/// never reaches the user.
String? dictionaryDownloadError(AppLocalizations l10n, Object? failure) =>
    switch (failure) {
      null => null,
      InsufficientSpaceException(:final neededBytes) =>
        l10n.backupFullNotEnoughSpace(size: formatBytes(neededBytes)),
      WifiLostException() => l10n.dictionaryDownloadWifiLost,
      DownloadStoppedInBackgroundException() =>
        l10n.downloadStoppedInBackground,
      // iOS ended its background work.
      DownloadStoppedException() => l10n.downloadInterrupted,
      // A part of the wrong size or hash.
      ModelVerificationException() => l10n.localOcrDownloadDamaged,
      DownloadHttpException(:final statusCode) ||
      ServerDownloadHttpException(
        :final statusCode,
      ) => l10n.serverBrowseDownloadFailed(
        error: l10n.serverErrorStatus(status: statusCode),
      ),
      ServerDownloadFailedException(:final error) =>
        recordedDownloadFailureText(l10n, RecordedDownloadFailure.parse(error)),
      SocketException() ||
      HttpException() ||
      TlsException() ||
      TimeoutException() => l10n.localOcrDownloadNetwork,
      _ when isStorageFull(failure) => l10n.localOcrStorageFull,
      // An archive that doesn't unpack (ArchiveException, a bad gzip) or a
      // hash that doesn't match (UniDic).
      FormatException() => l10n.localOcrDownloadDamaged,
      // An import or extraction that failed some other way.
      _ => l10n.downloadNotFinished,
    };

/// [dictionaryDownloadError] for a download with no Download button to tap
/// again (the lookup's speaker, the Anki button): a stop because Wi-Fi went
/// says only that.
String downloadErrorWithoutButton(AppLocalizations l10n, Object failure) =>
    failure is WifiLostException
    ? l10n.downloadWifiLostShort
    : dictionaryDownloadError(l10n, failure)!;

/// Why a model download (`runDownload`) failed, in the user's language.
String modelDownloadFailureReason(AppLocalizations l, Object error) =>
    error is WifiLostException
    ? l.localOcrWifiLostIos
    : dictionaryDownloadError(l, error)!;

/// The one wording of each failure a download worker records: all a model's
/// tile says, and a server book's message too except where the book's own
/// server says more (`describeServerDownloadError`). No default: a new kind
/// of failure is worded here before it compiles.
String recordedDownloadFailureText(
  AppLocalizations l10n,
  RecordedDownloadFailure failure,
) => switch (failure) {
  RecordedFailureCode.stopped => l10n.serverBrowseDownloadStopped,
  RecordedFailureCode.untrustedCertificate => l10n.serverCertificateUntrusted,
  RecordedFailureCode.interrupted => l10n.downloadInterrupted,
  RecordedFailureCode.connectionGone => l10n.serverErrorConnectionGone,
  RecordedFailureCode.storageFull => l10n.localOcrStorageFull,
  RecordedServerStatus(status: 0) => l10n.localOcrDownloadNetwork,
  RecordedServerStatus(:final status) => l10n.serverBrowseDownloadFailed(
    error: l10n.serverErrorStatus(status: status),
  ),
  // An exception's own text, or none.
  RecordedFailureCode.other => l10n.downloadNotFinished,
};
