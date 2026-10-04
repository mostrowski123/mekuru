import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Asks "Download over mobile data?" before a large download starts off
/// Wi-Fi. [body] names the size. True only when the user picks Download.
Future<bool> confirmMobileData(BuildContext context, String body) async {
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.localOcrMobileDownloadTitle),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonDownload),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Whether a large download may start now: on Wi-Fi, or off it once the
/// user agrees to use mobile data. [body] names the size.
Future<bool> okToDownload(BuildContext context, String body) async {
  if (await isOnWifi()) return true;
  if (!context.mounted) return false;
  return confirmMobileData(context, body);
}
