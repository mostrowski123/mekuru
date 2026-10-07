import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart'
    show ModelVerificationException;
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
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

/// Why a download (dictionary, translation or OCR model) failed, worded for
/// the user; null when it did not.
String? dictionaryDownloadError(AppLocalizations l10n, Object? failure) =>
    switch (failure) {
      null => null,
      InsufficientSpaceException(:final neededBytes) =>
        l10n.backupFullNotEnoughSpace(size: formatBytes(neededBytes)),
      WifiLostException() => l10n.dictionaryDownloadWifiLost,
      DownloadStoppedInBackgroundException() =>
        l10n.downloadStoppedInBackground,
      ModelVerificationException() => l10n.localOcrDownloadDamaged,
      DownloadHttpException(:final statusCode) ||
      ServerDownloadHttpException(
        :final statusCode,
      ) => l10n.serverBrowseDownloadFailed(
        error: l10n.serverErrorStatus(status: statusCode),
      ),
      ServerDownloadFailedException(:final error) => _recordedDownloadFailure(
        l10n,
        error,
      ),
      SocketException() ||
      HttpException() ||
      TlsException() ||
      TimeoutException() => l10n.localOcrDownloadNetwork,
      // ENOSPC
      FileSystemException(osError: OSError(errorCode: 28)) =>
        l10n.localOcrStorageFull,
      _ => l10n.serverBrowseDownloadFailed(error: '$failure'),
    };

/// A failure a download worker recorded ([ServerDownloadWorkStatus.error]).
String _recordedDownloadFailure(AppLocalizations l10n, String error) =>
    switch ((error, serverDownloadErrorStatus(error))) {
      (serverDownloadInterruptedError, _) => l10n.downloadInterrupted,
      (serverDownloadStoppedError, _) => l10n.serverBrowseDownloadStopped,
      (serverDownloadUntrustedCertificateError, _) =>
        l10n.serverCertificateUntrusted,
      (_, 0) => l10n.localOcrDownloadNetwork,
      (_, final int status) => l10n.serverBrowseDownloadFailed(
        error: l10n.serverErrorStatus(status: status),
      ),
      _ => l10n.serverBrowseDownloadFailed(error: error),
    };
