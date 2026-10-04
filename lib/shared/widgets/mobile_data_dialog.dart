import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

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

/// Starts [download] of a dictionary of [size] on Wi-Fi, or off it once the
/// user accepts mobile data. A dictionary download that started on Wi-Fi
/// stops if Wi-Fi goes, and tapping Download again must not then go on over
/// mobile data unasked. Pass the notifier's method itself: the tile can
/// unmount while the dialog is up.
Future<void> askThenDownload(
  BuildContext context,
  String size,
  Future<void> Function() download,
) async {
  AppHaptics.light();
  final body = context.l10n.catalogMobileDataBody(size: size);
  if (await okToDownload(context, body)) unawaited(download());
}
