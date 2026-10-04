import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:url_launcher/url_launcher.dart';

// Rows shown under a download tile: progress, an error, an attribution.

/// The label for [DictionaryDownloadService] progress: how much of the zip
/// has arrived, then the import.
String dictionaryDownloadLabel(AppLocalizations l10n, double progress) {
  const share = DictionaryDownloadService.downloadShare;
  return progress < share
      ? l10n.downloadsDownloadingPercent(
          percent: (progress / share * 100).toInt(),
        )
      : l10n.downloadsImporting;
}

class DownloadProgress extends StatelessWidget {
  const DownloadProgress({
    super.key,
    required this.progress,
    required this.label,
  });

  final double progress;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 13,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 13),
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

/// Why a dictionary download failed, worded for the user; null when it
/// did not.
String? dictionaryDownloadError(AppLocalizations l10n, Object? failure) =>
    switch (failure) {
      null => null,
      InsufficientSpaceException(:final neededBytes) =>
        l10n.backupFullNotEnoughSpace(size: formatBytes(neededBytes)),
      WifiLostException() => l10n.dictionaryDownloadWifiLost,
      _ => l10n.serverBrowseDownloadFailed(error: '$failure'),
    };
